import Foundation

// What each agent tool does. Reading tools answer straight away; the rest ask
// for approval through `requestAgentApproval` before they change anything.
extension MemoraModel {
  /// The most transcript sent for one record. Summaries and decisions go first,
  /// so a long meeting still gives the model what matters.
  private static let agentTranscriptLimit = 24_000

  /// `compact` is for the on-device model, whose whole context is a few
  /// thousand tokens: fewer results, shorter excerpts, no full transcripts.
  func performAgentTool(
    _ call: AgentToolCall,
    messageID: UUID,
    scope: AIChatScope,
    compact: Bool = false
  ) async -> AgentToolOutcome {
    guard let tool = call.tool else {
      if let external = activeMCPTools[call.name] {
        return await performMCPTool(external, call: call, messageID: messageID)
      }
      return AgentToolOutcome(text: "未知の道具です: \(call.name)", isError: true)
    }
    switch tool {
    case .searchRecords:
      return searchRecordsTool(call, messageID: messageID, scope: scope, compact: compact)
    case .readRecord:
      return readRecordTool(call, messageID: messageID, scope: scope, compact: compact)
    case .listProjects:
      return listProjectsTool(messageID: messageID)
    case .listTasks:
      return listTasksTool(call, messageID: messageID, scope: scope)
    case .readPerson:
      return readPersonTool(call, messageID: messageID, compact: compact)
    case .createDocument, .createSlides:
      return await createDocumentTool(call, tool: tool, messageID: messageID)
    case .addTasks:
      return await addTasksTool(call, messageID: messageID)
    case .createProject:
      return await createProjectTool(call, messageID: messageID)
    case .moveRecordsToProject:
      return await moveRecordsTool(call, messageID: messageID, scope: scope)
    case .addJournalMemo:
      return await addJournalMemoTool(call, messageID: messageID)
    case .createCalendarEvent:
      return await createCalendarEventTool(call, messageID: messageID)
    case .draftEmail:
      return await draftEmailTool(call, messageID: messageID)
    case .saveToNotion:
      return await saveToNotionTool(call, messageID: messageID, scope: scope)
    case .saveMemory:
      return await saveMemoryTool(call, messageID: messageID)
    case .searchEmail:
      return await searchEmailTool(call, messageID: messageID, compact: compact)
    case .readEmail:
      return await readEmailTool(call, messageID: messageID, compact: compact)
    }
  }

  // MARK: - Mail

  private func searchEmailTool(_ call: AgentToolCall, messageID: UUID, compact: Bool) async -> AgentToolOutcome {
    let query = call.string("query")
    let limit = min((call.arguments["limit"] as? Int) ?? 8, compact ? 5 : 15)
    let stepID = beginAgentStep(
      AgentStep(
        icon: AgentTool.searchEmail.icon,
        title: query.isEmpty ? "受信トレイを確認" : "メールを検索",
        query: query.isEmpty ? nil : query
      ),
      on: messageID
    )
    do {
      let messages = try await GmailService.shared.search(query, limit: limit)
      finishAgentStep(
        stepID,
        on: messageID,
        state: .done,
        detail: "\(messages.count)件",
        results: messages.map { AgentStep.Result(title: $0.subject, subtitle: $0.from) }
      )
      guard !messages.isEmpty else { return AgentToolOutcome(text: "該当するメールはありません。") }
      return AgentToolOutcome(text: messages.map { message in
        let date = message.date.map(Self.agentDate) ?? ""
        return "- id=\(message.id) \(date) 差出人: \(message.from) 件名: \(message.subject) 冒頭: \(message.snippet.prefix(compact ? 60 : 160))"
      }.joined(separator: "\n"))
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "読み込めませんでした")
      return AgentToolOutcome(text: error.localizedDescription, isError: true)
    }
  }

  private func readEmailTool(_ call: AgentToolCall, messageID: UUID, compact: Bool) async -> AgentToolOutcome {
    let id = call.string("id")
    guard !id.isEmpty else { return AgentToolOutcome(text: "idがありません。", isError: true) }
    let stepID = beginAgentStep(AgentStep(icon: AgentTool.readEmail.icon, title: "メールを読む"), on: messageID)
    do {
      let message = try await GmailService.shared.read(id)
      finishAgentStep(stepID, on: messageID, state: .done, detail: message.subject)
      let body = message.body.isEmpty ? message.snippet : message.body
      return AgentToolOutcome(text: """
      差出人: \(message.from)
      宛先: \(message.to)
      件名: \(message.subject)
      日時: \(message.date.map(Self.agentDate) ?? "不明")

      \(body.prefix(compact ? 1_500 : 12_000))
      """)
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "読み込めませんでした")
      return AgentToolOutcome(text: error.localizedDescription, isError: true)
    }
  }

  // MARK: - Memory

  private func saveMemoryTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    let text = call.string("text")
    guard !text.isEmpty else { return AgentToolOutcome(text: "覚える内容が空です。", isError: true) }
    guard isAIMemoryEnabled else {
      return AgentToolOutcome(text: "利用者はメモリをオフにしています。覚えずに続けてください。")
    }
    guard let stepID = await approve(
      tool: .saveMemory,
      title: "これを覚える",
      lines: [String(text.prefix(Self.aiMemoryCharacterLimit))],
      confirmTitle: "覚える",
      messageID: messageID
    ) else { return Self.declinedOutcome }
    let stored = addAIMemory(text, origin: .agent)
    finishAgentStep(stepID, on: messageID, state: .done, detail: stored ? nil : "すでに覚えています")
    return AgentToolOutcome(text: stored ? "覚えました。" : "すでに覚えている内容です。")
  }

  // MARK: - Reading

  private func searchRecordsTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope, compact: Bool) -> AgentToolOutcome {
    let query = call.string("query")
    let limit = compact ? 4 : min(max(call.int("limit") ?? 8, 1), 20)
    let previewLength = compact ? 80 : 200
    let stepID = beginAgentStep(
      AgentStep(
        icon: AgentTool.searchRecords.icon,
        title: query.isEmpty ? "最近の記録を確認" : "記録を検索",
        query: query.isEmpty ? nil : query
      ),
      on: messageID
    )

    let words = Self.questionWords(in: query)
    let allowed = Self.meetings(in: scope, from: meetings)
    let found: [Meeting]
    if words.isEmpty {
      found = Array(allowed.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    } else {
      found = Array(allowed
        .map { meeting in (meeting, words.filter { searchText(for: meeting).localizedCaseInsensitiveContains($0) }.count) }
        .filter { $0.1 > 0 }
        .sorted { ($0.1, $0.0.createdAt) > ($1.1, $1.0.createdAt) }
        .prefix(limit)
        .map(\.0))
    }

    // The journal has no project, so only the whole-library range reaches it.
    let entries: [LifeLogEntry]
    if scope == .all {
      let candidates = newestLifeLogEntries
      entries = Array((words.isEmpty ? candidates : candidates.filter { entry in
        words.contains { entry.title.localizedCaseInsensitiveContains($0) || entry.summary.localizedCaseInsensitiveContains($0) }
      }).prefix(limit))
    } else {
      entries = []
    }

    finishAgentStep(
      stepID,
      on: messageID,
      state: .done,
      detail: "記録\(found.count)件・ジャーナル\(entries.count)件",
      results: found.map { AgentStep.Result(title: $0.displayTitle, subtitle: Self.agentDate($0.createdAt), meetingID: $0.id) }
        + entries.map { AgentStep.Result(title: $0.title, subtitle: "ジャーナル") }
    )

    guard !found.isEmpty || !entries.isEmpty else {
      return AgentToolOutcome(text: "一致する記録はありません。別の言葉で検索してください。")
    }
    var lines: [String] = []
    for meeting in found {
      var line = "- 会議 id=\(meeting.id.uuidString) 「\(meeting.displayTitle)」 \(Self.agentDate(meeting.createdAt))"
      if let spaceID = meeting.spaceID, let space = space(id: spaceID) {
        line += " プロジェクト: \(space.name)"
      }
      let preview = meeting.summaryPreview.replacingOccurrences(of: "\n", with: " ")
      if !preview.isEmpty {
        line += " 概要: \(preview.prefix(previewLength))"
      }
      lines.append(line)
    }
    for entry in entries {
      let body = entry.summary.replacingOccurrences(of: "\n", with: " ")
      lines.append("- ジャーナル id=\(entry.id.uuidString) 「\(entry.title)」 \(Self.agentDate(entry.createdAt)) \(body.prefix(previewLength))")
    }
    return AgentToolOutcome(text: lines.joined(separator: "\n"))
  }

  private func readRecordTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope, compact: Bool) -> AgentToolOutcome {
    guard let id = UUID(uuidString: call.string("id")) else {
      return AgentToolOutcome(text: "idが正しくありません。search_recordsで得たidを使ってください。", isError: true)
    }

    let allowed = Self.meetings(in: scope, from: meetings)
    if let meeting = allowed.first(where: { $0.id == id }) {
      let stepID = beginAgentStep(
        AgentStep(icon: AgentTool.readRecord.icon, title: "「\(meeting.displayTitle)」を読む"),
        on: messageID
      )
      finishAgentStep(stepID, on: messageID, state: .done)
      return AgentToolOutcome(text: compact ? compactAgentText(of: meeting) : agentText(of: meeting))
    }

    if scope == .all, let entry = lifeLogEntries.first(where: { $0.id == id }) {
      let stepID = beginAgentStep(
        AgentStep(icon: AgentTool.readRecord.icon, title: "「\(entry.title)」を読む"),
        on: messageID
      )
      finishAgentStep(stepID, on: messageID, state: .done)
      var text = "ジャーナル「\(entry.title)」 \(Self.agentDate(entry.createdAt)) 種類: \(entry.kind.label)"
      if let location = entry.locationName, !location.isEmpty {
        text += " 場所: \(location)"
      }
      return AgentToolOutcome(text: text + "\n\(entry.summary)")
    }
    return AgentToolOutcome(text: "このidの記録は見つからないか、対象範囲の外です。", isError: true)
  }

  private func agentText(of meeting: Meeting) -> String {
    var parts = ["会議「\(meeting.displayTitle)」 \(Self.agentDate(meeting.createdAt)) 長さ: \(MemoraFormat.duration(meeting.duration))"]
    if let spaceID = meeting.spaceID, let space = space(id: spaceID) {
      parts.append("プロジェクト: \(space.name)（id=\(space.id.uuidString)）")
    }
    if !meeting.summary.isEmpty {
      parts.append("## 要約\n\(meeting.summary)")
    }
    if !meeting.keyPoints.isEmpty {
      parts.append("## 要点\n" + meeting.keyPoints.map { "- \($0)" }.joined(separator: "\n"))
    }
    if !meeting.decisions.isEmpty {
      parts.append("## 決定事項\n" + meeting.decisions.map { "- \($0)" }.joined(separator: "\n"))
    }
    if !meeting.openQuestions.isEmpty {
      parts.append("## 未解決の論点\n" + meeting.openQuestions.map { "- \($0)" }.joined(separator: "\n"))
    }
    let meetingTasks = tasks(forMeeting: meeting.id)
    if !meetingTasks.isEmpty {
      parts.append("## タスク\n" + meetingTasks.map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !meeting.notes.isEmpty {
      parts.append("## メモ\n\(meeting.notes)")
    }
    if !meeting.transcript.isEmpty {
      let showsSpeaker = meeting.hasSpeakerSeparation
      var transcript = ""
      for segment in meeting.transcript {
        let stamp = MemoraFormat.duration(segment.timestamp)
        let line = showsSpeaker && !segment.speaker.isEmpty
          ? "[\(stamp)] \(segment.speaker): \(segment.text)"
          : "[\(stamp)] \(segment.text)"
        guard transcript.count + line.count < Self.agentTranscriptLimit else {
          transcript += "\n（文字起こしはここで省略）"
          break
        }
        transcript += (transcript.isEmpty ? "" : "\n") + line
      }
      parts.append("## 文字起こし\n\(transcript)")
    }
    return parts.joined(separator: "\n\n")
  }

  /// A record cut to what fits the on-device model: the summary, decisions and
  /// tasks, and only a little of the transcript when there is no summary.
  private func compactAgentText(of meeting: Meeting) -> String {
    var parts = ["会議「\(meeting.displayTitle)」 \(Self.agentDate(meeting.createdAt))"]
    if !meeting.summary.isEmpty {
      parts.append("要約: \(meeting.summaryPreview.prefix(700))")
    }
    if !meeting.decisions.isEmpty {
      parts.append("決定: " + meeting.decisions.prefix(5).joined(separator: " / "))
    }
    let meetingTasks = tasks(forMeeting: meeting.id).filter { !$0.isCompleted }
    if !meetingTasks.isEmpty {
      parts.append("タスク: " + meetingTasks.prefix(5).map(\.title).joined(separator: " / "))
    }
    if meeting.summary.isEmpty, !meeting.transcript.isEmpty {
      parts.append("発言: " + meeting.transcript.map(\.text).joined(separator: " ").prefix(700))
    }
    return parts.joined(separator: "\n")
  }

  private func listProjectsTool(messageID: UUID) -> AgentToolOutcome {
    let stepID = beginAgentStep(AgentStep(icon: AgentTool.listProjects.icon, title: "プロジェクトを確認"), on: messageID)
    finishAgentStep(stepID, on: messageID, state: .done, detail: "\(spaces.count)件")
    guard !spaces.isEmpty else { return AgentToolOutcome(text: "プロジェクトはまだありません。") }
    return AgentToolOutcome(text: spaces.map { space in
      "- id=\(space.id.uuidString) 「\(space.name)」 記録\(spaceAggregates[space.id]?.meetingCount ?? 0)件"
    }.joined(separator: "\n"))
  }

  private func listTasksTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) -> AgentToolOutcome {
    let stepID = beginAgentStep(AgentStep(icon: AgentTool.listTasks.icon, title: "タスクを確認"), on: messageID)
    let allowed = Self.meetings(in: scope, from: meetings)
    var visible = call.bool("include_completed")
      ? (scope == .all ? tasks : Self.tasks(in: allowed, from: tasks))
      : Self.openTasks(in: scope, from: tasks, meetings: allowed)
    visible = Array(visible.prefix(80))
    finishAgentStep(stepID, on: messageID, state: .done, detail: "\(visible.count)件")
    guard !visible.isEmpty else { return AgentToolOutcome(text: "タスクはありません。") }
    return AgentToolOutcome(text: visible.map { task in
      var line = Self.agentTaskLine(task)
      if let meetingID = task.meetingID, let meeting = meeting(id: meetingID) {
        line += " 元の会議: 「\(meeting.displayTitle)」"
      }
      return line
    }.joined(separator: "\n"))
  }

  private func readPersonTool(_ call: AgentToolCall, messageID: UUID, compact: Bool) -> AgentToolOutcome {
    let name = call.string("name")
    guard !name.isEmpty else {
      let stepID = beginAgentStep(AgentStep(icon: AgentTool.readPerson.icon, title: "登録済みの人を確認"), on: messageID)
      finishAgentStep(stepID, on: messageID, state: .done, detail: "\(people.count)人")
      guard !people.isEmpty else { return AgentToolOutcome(text: "登録済みの人はいません。") }
      return AgentToolOutcome(text: people.map { "- \($0.name)" }.joined(separator: "\n"))
    }

    // The step names the person found, not the model's wording of the query.
    guard let person = person(named: name), let memory = memory(of: person.id) else {
      let stepID = beginAgentStep(AgentStep(icon: AgentTool.readPerson.icon, title: "「\(name)」を人物から探す"), on: messageID)
      finishAgentStep(stepID, on: messageID, state: .done, detail: "登録がありません")
      return AgentToolOutcome(text: "「\(name)」という人は登録されていません。search_recordsで名前を検索してください。")
    }
    let stepID = beginAgentStep(AgentStep(icon: AgentTool.readPerson.icon, title: "\(person.name)さんの記録を確認"), on: messageID)
    finishAgentStep(stepID, on: messageID, state: .done, detail: "会議\(memory.meetings.count)件")

    let meetingLimit = compact ? 4 : 12
    let taskLimit = compact ? 5 : 20
    var parts = ["\(person.name)さん"]
    if let note = person.note, !note.isEmpty { parts.append("メモ: \(note)") }
    if let lastMet = memory.lastMet {
      parts.append("最後に会った日: \(Self.agentDate(lastMet))、一緒の会議: \(memory.meetings.count)件")
    }
    if !memory.assignedTasks.isEmpty {
      parts.append("## 本人が引き受けたこと（未完了）\n" + memory.assignedTasks.prefix(taskLimit).map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !memory.sharedTasks.isEmpty {
      parts.append("## 一緒の会議で残っていること\n" + memory.sharedTasks.prefix(taskLimit).map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !memory.decisions.isEmpty {
      parts.append("## 一緒に決めたこと\n" + memory.decisions.prefix(taskLimit).map {
        "- \($0.text)（\($0.meetingTitle)、\(Self.agentDate($0.date))）"
      }.joined(separator: "\n"))
    }
    if !memory.meetings.isEmpty {
      parts.append("## 一緒の会議（新しい順）\n" + memory.meetings.prefix(meetingLimit).map { meeting in
        let preview = meeting.summaryPreview.replacingOccurrences(of: "\n", with: " ").prefix(compact ? 60 : 160)
        return "- id=\(meeting.id.uuidString) 「\(meeting.displayTitle)」 \(Self.agentDate(meeting.createdAt)) \(preview)"
      }.joined(separator: "\n"))
    }
    if !memory.journalEntries.isEmpty {
      parts.append("## ジャーナル\n" + memory.journalEntries.prefix(compact ? 3 : 8).map {
        "- \($0.title)（\(Self.agentDate($0.createdAt))）"
      }.joined(separator: "\n"))
    }
    return AgentToolOutcome(text: parts.joined(separator: "\n\n"))
  }

  // MARK: - Changing

  private func createDocumentTool(_ call: AgentToolCall, tool: AgentTool, messageID: UUID) async -> AgentToolOutcome {
    let title = call.string("title")
    let projectID = UUID(uuidString: call.string("project_id")).flatMap { space(id: $0)?.id }
    var document = MemoraDocument(
      title: title,
      kind: tool == .createSlides ? .slides : .document,
      spaceID: projectID
    )
    var lines = [document.displayTitle]
    switch document.kind {
    case .document:
      document.markdown = call.string("markdown")
      guard !document.markdown.isEmpty else {
        return AgentToolOutcome(text: "markdownが空です。本文を書いてください。", isError: true)
      }
      lines.append("約\(document.markdown.count)文字")
      let headings = document.markdown
        .components(separatedBy: .newlines)
        .filter { $0.hasPrefix("#") }
        .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
        .prefix(4)
      lines += headings.map { "・\($0)" }
    case .slides:
      document.slides = call.objects("slides").map { slide in
        DocumentSlide(
          title: (slide["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
          bullets: (slide["bullets"] as? [Any] ?? []).compactMap { $0 as? String },
          notes: slide["notes"] as? String ?? ""
        )
      }
      guard !document.slides.isEmpty else {
        return AgentToolOutcome(text: "slidesが空です。スライドを1枚以上書いてください。", isError: true)
      }
      lines.append("\(document.slides.count)枚")
      lines += document.slides.prefix(4).map { "・\($0.title)" }
    }
    if let projectID, let space = space(id: projectID) {
      lines.append("プロジェクト: \(space.name)")
    }

    let kindLabel = document.kind.label
    let approved = await approve(
      tool: tool,
      title: "\(kindLabel)を作成",
      lines: lines,
      confirmTitle: "作成",
      messageID: messageID
    )
    guard let stepID = approved else { return Self.declinedOutcome }

    guard addDocument(document) else {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "保存できませんでした")
      return AgentToolOutcome(text: "保存に失敗しました。", isError: true)
    }
    updateAgentMessage(messageID) { $0.documentIDs.append(document.id) }
    finishAgentStep(stepID, on: messageID, state: .done, detail: document.displayTitle)
    return AgentToolOutcome(text: "\(kindLabel)を保存しました。id=\(document.id.uuidString)")
  }

  private func addTasksTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    struct Draft {
      var title: String
      var assignee: String
      var dueDate: Date?
      var meetingID: UUID?
    }
    let drafts = call.objects("tasks").compactMap { item -> Draft? in
      let title = (item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else { return nil }
      let meetingID = (item["meeting_id"] as? String).flatMap(UUID.init(uuidString:)).flatMap { meeting(id: $0)?.id }
      return Draft(
        title: title,
        assignee: item["assignee"] as? String ?? "",
        dueDate: (item["due_date"] as? String).flatMap(Self.agentDay),
        meetingID: meetingID
      )
    }
    guard !drafts.isEmpty else {
      return AgentToolOutcome(text: "追加するタスクがありません。", isError: true)
    }

    let lines = drafts.map { draft in
      var line = "・\(draft.title)"
      if !draft.assignee.isEmpty { line += "（\(draft.assignee)）" }
      if let due = draft.dueDate { line += " 期限 \(due.formatted(.dateTime.month().day()))" }
      return line
    }
    guard let stepID = await approve(
      tool: .addTasks,
      title: "タスクを\(drafts.count)件追加",
      lines: lines,
      confirmTitle: "追加",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    for draft in drafts.reversed() {
      addTask(title: draft.title, assignee: draft.assignee, dueDate: draft.dueDate, meetingID: draft.meetingID)
    }
    finishAgentStep(stepID, on: messageID, state: .done, detail: "\(drafts.count)件")
    return AgentToolOutcome(text: "タスクを\(drafts.count)件追加しました。")
  }

  private func createProjectTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    let name = call.string("name")
    guard !name.isEmpty else {
      return AgentToolOutcome(text: "プロジェクト名が空です。", isError: true)
    }
    if let existing = spaces.first(where: { $0.name == name }) {
      return AgentToolOutcome(text: "同じ名前のプロジェクトがあります。id=\(existing.id.uuidString)")
    }
    guard let stepID = await approve(
      tool: .createProject,
      title: "プロジェクトを作成",
      lines: [name],
      confirmTitle: "作成",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    guard let id = addSpace(name: name) else {
      finishAgentStep(stepID, on: messageID, state: .failed)
      return AgentToolOutcome(text: "作成できませんでした。", isError: true)
    }
    finishAgentStep(stepID, on: messageID, state: .done, detail: name)
    return AgentToolOutcome(text: "プロジェクトを作成しました。id=\(id.uuidString)")
  }

  private func moveRecordsTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) async -> AgentToolOutcome {
    guard let projectID = UUID(uuidString: call.string("project_id")), let space = space(id: projectID) else {
      return AgentToolOutcome(text: "プロジェクトが見つかりません。list_projectsのidを使ってください。", isError: true)
    }
    let allowed = Self.meetings(in: scope, from: meetings)
    let records = call.strings("record_ids")
      .compactMap(UUID.init(uuidString:))
      .compactMap { id in allowed.first { $0.id == id } }
    guard !records.isEmpty else {
      return AgentToolOutcome(text: "移動できる記録がありません。会議の記録のidを指定してください。", isError: true)
    }

    guard let stepID = await approve(
      tool: .moveRecordsToProject,
      title: "\(records.count)件を「\(space.name)」へ移動",
      lines: records.map { "・\($0.displayTitle)" },
      confirmTitle: "移動",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    moveMeetings(Set(records.map(\.id)), to: space.id)
    finishAgentStep(stepID, on: messageID, state: .done, detail: space.name)
    return AgentToolOutcome(text: "\(records.count)件を移動しました。")
  }

  private func addJournalMemoTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    let title = call.string("title")
    let body = call.string("body")
    guard !title.isEmpty || !body.isEmpty else {
      return AgentToolOutcome(text: "メモが空です。", isError: true)
    }
    guard let stepID = await approve(
      tool: .addJournalMemo,
      title: "ジャーナルにメモを追加",
      lines: [title, String(body.prefix(120))].filter { !$0.isEmpty },
      confirmTitle: "追加",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    let stored = addLifeLogEntry(
      kind: .memo,
      title: title,
      summary: body,
      createdAt: .now,
      photoData: nil,
      eventDate: nil,
      locationName: nil
    )
    finishAgentStep(stepID, on: messageID, state: stored ? .done : .failed, detail: stored ? nil : "保存できませんでした")
    return stored
      ? AgentToolOutcome(text: "ジャーナルに追加しました。")
      : AgentToolOutcome(text: "保存に失敗しました。", isError: true)
  }

  private func createCalendarEventTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    let title = call.string("title")
    guard !title.isEmpty, let start = Self.agentDateTime(call.string("start")) else {
      return AgentToolOutcome(text: "titleとstart（yyyy-MM-dd HH:mm）が必要です。", isError: true)
    }
    let minutes = min(max(call.int("duration_minutes") ?? 60, 5), 24 * 60)
    let end = start.addingTimeInterval(TimeInterval(minutes * 60))
    let location = call.string("location")
    let notes = call.string("notes")

    var lines = [title, "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"]
    if !location.isEmpty { lines.append("場所: \(location)") }
    guard let stepID = await approve(
      tool: .createCalendarEvent,
      title: "カレンダーに予定を追加",
      lines: lines,
      confirmTitle: "追加",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    do {
      try await CalendarService.addEvent(
        title: title,
        start: start,
        end: end,
        location: location.isEmpty ? nil : location,
        notes: notes.isEmpty ? nil : notes
      )
      finishAgentStep(stepID, on: messageID, state: .done, detail: title)
      return AgentToolOutcome(text: "カレンダーに追加しました。")
    } catch CalendarService.AddEventError.accessDenied {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "カレンダーへのアクセスが許可されていません")
      return AgentToolOutcome(text: "カレンダーへのアクセスが許可されていないため追加できませんでした。設定アプリで許可するよう伝えてください。", isError: true)
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "追加できませんでした")
      return AgentToolOutcome(text: "カレンダーに追加できませんでした。", isError: true)
    }
  }

  private func draftEmailTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    let subject = call.string("subject")
    let body = call.string("body")
    guard !body.isEmpty else {
      return AgentToolOutcome(text: "本文が空です。", isError: true)
    }
    // Only addresses are kept; a name alone cannot be sent to.
    let recipients = call.strings("to").filter { $0.contains("@") }

    var lines = ["件名: \(subject.isEmpty ? "（なし）" : subject)"]
    if !recipients.isEmpty { lines.append("宛先: \(recipients.joined(separator: ", "))") }
    lines.append(String(body.prefix(160)))
    guard let stepID = await approve(
      tool: .draftEmail,
      title: "メールの下書きを開く",
      lines: lines,
      confirmTitle: "開く",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    pendingMailDraft = MailDraft(recipients: recipients, subject: subject, body: body)
    finishAgentStep(stepID, on: messageID, state: .done, detail: subject)
    return AgentToolOutcome(text: "下書きを開きました。送信するかどうかは利用者が決めます。")
  }

  private func saveToNotionTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) async -> AgentToolOutcome {
    guard NotionService.isConfigured else {
      return AgentToolOutcome(text: "Notionが連携されていません。設定の「Notion」で連携するよう伝えてください。", isError: true)
    }
    let allowed = Self.meetings(in: scope, from: meetings)
    guard let id = UUID(uuidString: call.string("meeting_id")), let meeting = allowed.first(where: { $0.id == id }) else {
      return AgentToolOutcome(text: "会議の記録が見つかりません。search_recordsのidを使ってください。", isError: true)
    }
    guard let stepID = await approve(
      tool: .saveToNotion,
      title: "Notionに保存",
      lines: [meeting.displayTitle],
      confirmTitle: "保存",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    do {
      let outcome = try await NotionService.save(meeting: meeting, tasks: tasks)
      finishAgentStep(stepID, on: messageID, state: .done, detail: meeting.displayTitle)
      return AgentToolOutcome(text: "Notionに保存しました。\(outcome.pageURL?.absoluteString ?? "")")
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "保存できませんでした")
      return AgentToolOutcome(text: "Notionに保存できませんでした。", isError: true)
    }
  }

  // MARK: - Helpers

  /// Shows the step and the approval card. Returns the step's id when approved,
  /// so the caller can settle it, or nil when declined.
  private func approve(
    tool: AgentTool,
    title: String,
    lines: [String],
    confirmTitle: String,
    messageID: UUID
  ) async -> UUID? {
    let stepID = beginAgentStep(AgentStep(icon: tool.icon, title: title, detail: "確認待ち"), on: messageID)
    let approved = await requestAgentApproval(AgentApproval(
      messageID: messageID,
      icon: tool.icon,
      title: title,
      lines: lines,
      confirmTitle: confirmTitle
    ))
    guard approved, !Task.isCancelled else {
      finishAgentStep(stepID, on: messageID, state: .declined, detail: "取りやめました")
      return nil
    }
    finishAgentStep(stepID, on: messageID, state: .running, detail: "")
    return stepID
  }

  private static let declinedOutcome = AgentToolOutcome(
    text: "利用者がこの操作を承認しませんでした。同じ操作を繰り返さず、必要なら理由を尋ねてください。"
  )

  private static func agentTaskLine(_ task: MemoraTask) -> String {
    var line = "- \(task.isCompleted ? "[完了] " : "")\(task.title)"
    if let assignee = task.assignee, !assignee.isEmpty { line += " 担当: \(assignee)" }
    if let due = task.dueDate { line += " 期限: \(agentDate(due))" }
    return line
  }

  private static func agentDate(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
  }

  /// Reads `yyyy-MM-dd HH:mm` in the person's time zone.
  private static func agentDateTime(_ text: String) -> Date? {
    let parts = text.split(whereSeparator: { $0 == " " || $0 == "T" })
    guard let dayPart = parts.first, let day = agentDay(String(dayPart)) else { return nil }
    guard parts.count > 1 else { return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) }
    let time = parts[1].split(separator: ":").compactMap { Int($0) }
    guard time.count >= 2 else { return nil }
    return Calendar.current.date(bySettingHour: time[0], minute: time[1], second: 0, of: day)
  }

  /// Reads a `yyyy-MM-dd` day in the person's calendar.
  private static func agentDay(_ text: String) -> Date? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}
