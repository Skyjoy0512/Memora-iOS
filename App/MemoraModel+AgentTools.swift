import Foundation

// What each agent tool does. Reading tools answer straight away; the rest ask
// for approval through `requestAgentApproval` before they change anything.
extension MemoraModel {
  /// The most transcript sent for one record. Summaries and decisions go first,
  /// so a long meeting still gives the model what matters.
  private static let agentTranscriptLimit = 24_000

  func performAgentTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) async -> AgentToolOutcome {
    guard let tool = call.tool else {
      return AgentToolOutcome(text: "未知の道具です: \(call.name)", isError: true)
    }
    switch tool {
    case .searchRecords:
      return searchRecordsTool(call, messageID: messageID, scope: scope)
    case .readRecord:
      return readRecordTool(call, messageID: messageID, scope: scope)
    case .listProjects:
      return listProjectsTool(messageID: messageID)
    case .listTasks:
      return listTasksTool(call, messageID: messageID, scope: scope)
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
    }
  }

  // MARK: - Reading

  private func searchRecordsTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) -> AgentToolOutcome {
    let query = call.string("query")
    let limit = min(max(call.int("limit") ?? 8, 1), 20)
    let stepID = beginAgentStep(
      AgentStep(icon: AgentTool.searchRecords.icon, title: query.isEmpty ? "最近の記録を確認" : "「\(query)」を検索"),
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

    finishAgentStep(stepID, on: messageID, state: .done, detail: "記録\(found.count)件・ジャーナル\(entries.count)件")

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
        line += " 概要: \(preview.prefix(200))"
      }
      lines.append(line)
    }
    for entry in entries {
      let body = entry.summary.replacingOccurrences(of: "\n", with: " ")
      lines.append("- ジャーナル id=\(entry.id.uuidString) 「\(entry.title)」 \(Self.agentDate(entry.createdAt)) \(body.prefix(200))")
    }
    return AgentToolOutcome(text: lines.joined(separator: "\n"))
  }

  private func readRecordTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) -> AgentToolOutcome {
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
      return AgentToolOutcome(text: agentText(of: meeting))
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

  /// Reads a `yyyy-MM-dd` day in the person's calendar.
  private static func agentDay(_ text: String) -> Date? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}
