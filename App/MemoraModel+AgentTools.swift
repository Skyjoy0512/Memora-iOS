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
    compact: Bool = false,
    automaticAccess: Bool = false
  ) async -> AgentToolOutcome {
    if let policy = agentPluginPolicies[messageID], let personID = policy.personID {
      guard aiPersonScopeID == personID, person(id: personID) != nil,
            policy.recordIDs.isSubset(of: Set(meetings(withPerson: personID).map(\.id))) else {
        return AgentToolOutcome(text: "人物の参照範囲が変更されました。新しい依頼を送ってください。", isError: true)
      }
    }
    guard consumeAgentToolCall(messageID) else { return AgentToolOutcome(text: "ツール実行上限（1回答24回）に達したため停止しました。", isError: true) }
    guard pluginCallIsPermitted(call, messageID: messageID) else {
      return AgentToolOutcome(text: "@で指定した対象以外のツールや記録にはアクセスできません。必要な対象を明示的に追加してください。", isError: true)
    }
    guard !agentBlockedExternalTools[messageID, default: []].contains(call.name) else {
      return AgentToolOutcome(text: "この依頼では実行を拒否されたか失敗したため、再実行しません。必要なら接続設定を確認して新しい依頼を送ってください。", isError: true)
    }
    guard toolRegistry().permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID]) else {
      return AgentToolOutcome(text: "存在しない、無効、または入力形式に対応していない道具です。実行していません。", isError: true)
    }
    if call.tool == .readRecord, let id = UUID(uuidString: call.string("id")), source(id: id) != nil {
      return await readAgentProjectSource(id, messageID: messageID, compact: compact, automatic: automaticAccess)
    }
    if call.tool == .searchEmail || call.tool == .readEmail {
      guard !automaticAccess else {
        return AgentToolOutcome(text: "料金未確認のメール取得は自動処理では実行できません。チャットから明示的に依頼してください。", isError: true)
      }
      if let refusal = await directPluginReadRefusal(call, messageID: messageID) { return refusal }
    }
    if compact, agentPluginPolicies[messageID]?.personID != nil,
       let outcome = automaticRecordTool(call, messageID: messageID, purpose: .cloudAI, scope: scope) { return outcome }
    if automaticAccess {
      guard let tool = call.tool, AgentTool.residentTools.contains(tool) else {
        return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
      }
      if let outcome = automaticRecordTool(call, messageID: messageID) { return outcome }
    } else if !compact, let outcome = automaticRecordTool(call, messageID: messageID, purpose: .cloudAI, scope: scope) {
      return outcome
    }
    guard let tool = call.tool else {
      if let external = activeMCPTools[call.name] {
        let outcome = await performMCPTool(external, call: call, messageID: messageID)
        if !compact { markCloudProvenanceIncomplete(messageID) }
        return outcome
      }
      return AgentToolOutcome(text: "未知の道具です: \(call.name)", isError: true)
    }
    if !compact { markCloudProvenanceIncomplete(messageID) }
    switch tool {
    case .searchWeb, .deepResearch:
      return await webResearchTool(call, messageID: messageID, compact: compact)
    case .delegateResearch:
      return AgentToolOutcome(text: "分担調査はクラウドの主担当からだけ開始できます。", isError: true)
    case .searchRecords:
      return searchRecordsTool(call, messageID: messageID, scope: scope, compact: compact)
    case .readRecord:
      return readRecordTool(call, messageID: messageID, scope: scope, compact: compact)
    case .listProjects:
      updateAgentMessage(messageID) { $0.interfaceProjectIDs.formUnion(spaces.map(\.id)); $0.interfaceWorkspaceID = currentTeamID }
      return listProjectsTool(messageID: messageID)
    case .listTasks:
      return listTasksTool(call, messageID: messageID, scope: scope)
    case .reviewPeriod:
      return reviewPeriodTool(call, messageID: messageID, scope: scope)
    case .updateTasks:
      return await updateTasksTool(call, messageID: messageID, scope: scope)
    case .readPerson:
      return readPersonTool(call, messageID: messageID, compact: compact)
    case .createDocument, .createSlides:
      return await createDocumentTool(call, tool: tool, messageID: messageID)
    case .addTasks:
      return await addTasksTool(call, messageID: messageID, scope: scope)
    case .createProject:
      return await createProjectTool(call, messageID: messageID)
    case .moveRecordsToProject:
      return await moveRecordsTool(call, messageID: messageID, scope: scope)
    case .addJournalMemo:
      return await addJournalMemoTool(call, messageID: messageID)
    case .readCalendar:
      return await readCalendarTool(call, messageID: messageID)
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
    case .askUser:
      return await askUserTool(call, messageID: messageID)
    }
  }

  // MARK: - Asking

  private func askUserTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    let raw = call.arguments["questions"] as? [[String: Any]] ?? []
    let questions = raw.prefix(3).compactMap { item -> AgentQuestion? in
      let text = (item["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let options = (item["options"] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard !text.isEmpty, !options.isEmpty else { return nil }
      return AgentQuestion(text: text, allowsMultiple: item["multiple"] as? Bool ?? false, options: Array(options.prefix(5)))
    }
    guard !questions.isEmpty else { return AgentToolOutcome(text: "質問が空です。", isError: true) }

    let stepID = beginAgentStep(AgentStep(icon: AgentTool.askUser.icon, title: "質問しました", detail: "回答待ち"), on: messageID)
    let answers = await requestAgentQuestions(AgentQuestionRequest(messageID: messageID, questions: questions))
    guard let answers, !Task.isCancelled else {
      finishAgentStep(stepID, on: messageID, state: .declined, detail: "回答なし")
      return AgentToolOutcome(text: "利用者は質問に答えずに閉じました。分かっている範囲で進めるか、何が必要か短く伝えてください。")
    }
    finishAgentStep(stepID, on: messageID, state: .done, detail: "\(answers.filter { !$0.isEmpty }.count)問に回答")
    let lines = zip(questions, answers).map { question, answer in
      "Q: \(question.text)\nA: \(answer.isEmpty ? "（回答なし）" : answer)"
    }
    return AgentToolOutcome(text: lines.joined(separator: "\n\n"))
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
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      return AgentToolOutcome(text: ExternalToolFailure.message(for: error), isError: true)
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
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      return AgentToolOutcome(text: ExternalToolFailure.message(for: error), isError: true)
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
    let exists = visibleAIMemories.contains { $0.text.caseInsensitiveCompare(text) == .orderedSame }
    let stored = addAIMemory(text, origin: .agent, sourceReference: "conversation:\(aiConversationID)")
    let fingerprint = cloudMemoryFingerprint
    updateAgentMessage(messageID) { $0.cloudProvenance?.memoryFingerprint = fingerprint }
    finishAgentStep(stepID, on: messageID, state: stored || exists ? .done : .failed, detail: stored ? nil : exists ? "すでに覚えています" : "保存できませんでした")
    if !stored && !exists { return AgentToolOutcome(text: "記憶を保存できませんでした。保存先を確認してください。", isError: true) }
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
      let candidates = newestLifeLogEntries.filter {
        AIJournalPrivacy.allowsReading(kind: $0.kind, origin: $0.origin)
      }
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
      lines.append("- ジャーナル id=\(entry.id.uuidString) 「\(entry.title)」 \(Self.agentDate(entry.occurredAt)) \(body.prefix(previewLength))")
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
      // A record the agent read is what its answer rests on; follow-ups are
      // built from it.
      updateAgentMessage(messageID) { message in
        if !message.sources.contains(where: { $0.meetingID == meeting.id }) {
          message.sources.append(AIChatSource(meetingID: meeting.id, title: meeting.displayTitle))
        }
      }
      return AgentToolOutcome(text: compact ? compactAgentText(of: meeting) : agentText(of: meeting))
    }

    if scope == .all, let entry = lifeLogEntries.first(where: {
      $0.id == id && AIJournalPrivacy.allowsReading(kind: $0.kind, origin: $0.origin)
    }) {
      let stepID = beginAgentStep(
        AgentStep(icon: AgentTool.readRecord.icon, title: "「\(entry.title)」を読む"),
        on: messageID
      )
      finishAgentStep(stepID, on: messageID, state: .done)
      let text = "ジャーナル「\(entry.title)」 \(Self.agentDate(entry.occurredAt)) 種類: \(entry.kind.label)"
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
    updateAgentMessage(messageID) { $0.interfaceTaskIDs.formUnion(visible.map(\.id)); $0.interfaceWorkspaceID = currentTeamID }
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

  func readPersonTool(_ call: AgentToolCall, messageID: UUID, compact: Bool, purpose: RecordAccessPolicy.Purpose? = nil) -> AgentToolOutcome {
    guard !isRestoring, !isStoreProtected else { return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true) }
    let name = call.string("name")
    let explicitID = call.string("person_id")
    let candidates: [Person]
    if !explicitID.isEmpty {
      guard let id = UUID(uuidString: explicitID), let person = person(id: id) else {
        return AgentToolOutcome(text: "人物IDが無効です。人物を選び直してください。", isError: true)
      }
      candidates = [person]
    } else { candidates = PersonIdentity.candidates(for: name, in: people) }
    guard !name.isEmpty || !explicitID.isEmpty, candidates.count == 1, let person = candidates.first,
          var memory = memory(of: person.id) else {
      return AgentToolOutcome(text: candidates.isEmpty ? "該当する人物はいません。" :
        "人物候補です。複数なら本人に確認し、person_idで指定してください。\n" + candidates.prefix(30).map { "id=\($0.id) \($0.name)" }.joined(separator: "\n"))
    }
    if let policy = agentPluginPolicies[messageID], policy.personID != nil {
      memory.meetings = memory.meetings.filter { policy.recordIDs.contains($0.id) }
      memory.assignedTasks = memory.assignedTasks.filter { $0.meetingID.map(policy.recordIDs.contains) == true }
      memory.sharedTasks = memory.sharedTasks.filter { $0.meetingID.map(policy.recordIDs.contains) == true }
      memory.journalEntries = []
      memory.decisions = memory.decisions.filter { policy.recordIDs.contains($0.meetingID) }
    }
    if let purpose {
      memory.meetings = memory.meetings.filter { allowsRecordAccess($0.id, purpose: purpose) }
      memory.assignedTasks = memory.assignedTasks.filter { allowsTaskAccess($0, purpose: purpose) }
      memory.sharedTasks = memory.sharedTasks.filter { allowsTaskAccess($0, purpose: purpose) }
      memory.journalEntries = memory.journalEntries.filter { allowsJournalAccess($0, purpose: purpose) }
      let ids = Set(memory.meetings.map(\.id))
      memory.decisions = memory.decisions.filter { ids.contains($0.meetingID) }
      recordCloudReads(memory.meetings.map { .meeting($0.id) }
        + (memory.assignedTasks + memory.sharedTasks).map { .task($0.id) }
        + memory.journalEntries.map { .journal($0.id) }, messageID: messageID)
    }
    // Person metadata has no independent cloud grant or fingerprint yet.
    if !compact { markCloudProvenanceIncomplete(messageID) }
    let stepID = beginAgentStep(AgentStep(icon: AgentTool.readPerson.icon, title: "\(person.name)さんの記録を確認"), on: messageID)
    finishAgentStep(stepID, on: messageID, state: .done, detail: "会議\(memory.meetings.count)件")

    let meetingLimit = compact ? 4 : 12
    let taskLimit = compact ? 5 : 20
    var parts = ["\(person.name)さん"]
    if purpose == nil, let note = person.note, !note.isEmpty { parts.append("メモ: \(note)") }
    if let lastMet = memory.lastMet {
      parts.append("最後に会った日: \(Self.agentDate(lastMet))、一緒の会議: \(memory.meetings.count)件")
    }
    if !memory.assignedTasks.isEmpty {
      parts.append("## 担当名が一致する未完了タスク（旧形式の名前照合）\n" + memory.assignedTasks.prefix(taskLimit).map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !memory.sharedTasks.isEmpty {
      parts.append("## 一緒の会議で残っていること\n" + memory.sharedTasks.prefix(taskLimit).map(Self.agentTaskLine).joined(separator: "\n"))
    }
    if !memory.decisions.isEmpty {
      parts.append("## 関連する会議の決定（本人の発言・合意とは断定しない）\n" + memory.decisions.prefix(taskLimit).map {
        "- \($0.text)（\($0.meetingTitle)、\(Self.agentDate($0.date))）"
      }.joined(separator: "\n"))
    }
    if !memory.meetings.isEmpty {
      parts.append("## 一緒の会議（新しい順）\n" + memory.meetings.prefix(meetingLimit).map { meeting in
        let preview = meeting.summaryPreview.replacingOccurrences(of: "\n", with: " ").prefix(compact ? 60 : 160)
        return "- id=\(meeting.id.uuidString) 「\(meeting.displayTitle)」 \(Self.agentDate(meeting.createdAt)) \(preview)"
      }.joined(separator: "\n"))
    }
    let journalEntries = memory.journalEntries.filter {
      AIJournalPrivacy.allowsReading(kind: $0.kind, origin: $0.origin)
    }
    if !journalEntries.isEmpty {
      parts.append("## ジャーナル\n" + journalEntries.prefix(compact ? 3 : 8).map {
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

    if let message = agentMessage(messageID) {
      document.sourceRecordIDs = message.sources.map(\.meetingID)
      document.sourceProjectFileIDs = message.projectSourceReferences.map(\.id)
      if document.kind == .document, !message.sources.isEmpty {
        var citationMessage = message
        citationMessage.text = document.markdown
        document.markdown = AIAnswerDocumentBuilder.make(message: citationMessage, question: document.title).markdown
      }
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

    do {
      document = try await prepareDocumentArtifact(document, call: call)
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "ファイルを作成できませんでした")
      return AgentToolOutcome(text: error.localizedDescription, isError: true)
    }
    guard !Task.isCancelled, agentMessage(messageID) != nil, pluginCallIsPermitted(call, messageID: messageID),
          (agentMessage(messageID)?.cloudProvenance == nil || isCloudSessionAuthorized(messageID)), addDocument(document) else {
      if let name = document.artifactFileReference { await ProjectSourceFiles.shared.remove([name]) }
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "保存できませんでした")
      return AgentToolOutcome(text: "保存に失敗しました。", isError: true)
    }
    updateAgentMessage(messageID) { $0.documentIDs.append(document.id) }
    finishAgentStep(stepID, on: messageID, state: .done, detail: document.displayTitle)
    return AgentToolOutcome(text: "\(document.artifactFormat ?? kindLabel)ファイルを生成・再読込検証し、資料として保存しました。id=\(document.id.uuidString)。最終フォント・改ページ・文字あふれはプレビューで確認してください。")
  }

  private func addTasksTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) async -> AgentToolOutcome {
    guard !isRestoring, !isStoreProtected else { return AgentToolOutcome(text: "保存先を確認できないため追加できません。", isError: true) }
    defer { approvedAgentTaskDrafts.removeValue(forKey: messageID) }
    let drafts: [AgentTaskDraft]
    do { drafts = try AgentTaskDraft.parse(call.objects("tasks")) }
    catch { return AgentToolOutcome(text: "候補のタイトル・詳細・担当・期限を確認してください。タスクは追加していません。", isError: true) }
    let scopedMeetingIDs = Set(Self.meetings(in: scope, from: meetings).map(\.id))
    guard drafts.allSatisfy({ $0.meetingID.map(scopedMeetingIDs.contains) ?? true }) else {
      return AgentToolOutcome(text: "対象外または存在しない会議が指定されています。タスクは追加していません。", isError: true)
    }
    let workspaceID = currentTeamID
    let stepID = beginAgentStep(AgentStep(icon: .checklist, title: "タスク候補を確認しています", detail: "確認待ち"), on: messageID)
    let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .checklist,
      title: "タスクを\(drafts.count)件追加", lines: [], confirmTitle: "追加", taskDrafts: drafts))
    guard approved, !Task.isCancelled else {
      finishAgentStep(stepID, on: messageID, state: .declined)
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      return Self.declinedOutcome
    }
    let allowedIDs = Set(Self.meetings(in: scope, from: meetings).map(\.id))
    guard !isRestoring, !isStoreProtected, currentTeamID == workspaceID, agentMessage(messageID) != nil,
          toolRegistry().permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID]),
          let edited = approvedAgentTaskDrafts.removeValue(forKey: messageID),
          let selected = AgentTaskDraft.validatedSelection(edited, originals: drafts, allowedMeetingIDs: allowedIDs),
          selected.allSatisfy({ draft in
            agentMessage(messageID)?.cloudProvenance == nil || (draft.meetingID.map { allowsRecordAccess($0, purpose: .cloudAI) } ?? true)
          }) else {
      finishAgentStep(stepID, on: messageID, state: .failed)
      return AgentToolOutcome(text: "候補・権限・ワークスペースが変わりました。タスクは追加していません。", isError: true)
    }
    var existing = tasks.filter { !$0.isCompleted }
    var additions: [MemoraTask] = []
    var skipped = 0
    for draft in selected {
      let candidate = MemoraTask(id: draft.id, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
        meetingID: draft.meetingID, assignee: draft.assignee.isEmpty ? nil : draft.assignee,
        dueDate: draft.dueDate, isCompleted: false, detail: draft.detail)
      if existing.contains(where: { Self.matchesTaskProposal($0, candidate) }) { skipped += 1; continue }
      additions.append(candidate)
      existing.append(candidate)
    }
    if !additions.isEmpty, !insertTasks(additions) {
      finishAgentStep(stepID, on: messageID, state: .failed)
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      return AgentToolOutcome(text: "保存できませんでした。タスクは追加していません。", isError: true)
    }
    // One approved batch per reply prevents another model turn from repeating it.
    agentBlockedExternalTools[messageID, default: []].insert(call.name)
    updateAgentMessage(messageID) { $0.createdTaskIDs.append(contentsOf: additions.map(\.id)) }
    finishAgentStep(stepID, on: messageID, state: .done, detail: "\(additions.count)件")
    let duplicateNote = skipped > 0 ? " 同じ内容の未完了タスク\(skipped)件は追加していません。" : ""
    return AgentToolOutcome(text: "承認された内容でタスクを\(additions.count)件追加しました。" + duplicateNote
      + " 候補は利用者が編集している場合があります。完了報告はこの件数を使い、編集前のタイトル・担当・期限を保存済みと報告しないでください。")
  }

  private static func matchesTaskProposal(_ left: MemoraTask, _ right: MemoraTask) -> Bool {
    left.title == right.title && left.detail == right.detail && left.assignee == right.assignee
      && left.meetingID == right.meetingID && left.dueDate == right.dueDate
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

    guard moveMeetings(Set(records.map(\.id)), to: space.id) else {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "移動を保存できませんでした")
      return AgentToolOutcome(text: "移動を保存できませんでした。元のプロジェクトは変更していません。", isError: true)
    }
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
    let recipients = call.strings("to")
    let cc = call.strings("cc"), bcc = call.strings("bcc")
    guard (recipients + cc + bcc).allSatisfy(MailDraft.validAddress) else {
      return AgentToolOutcome(text: "宛先は確認済みのメールアドレスだけにしてください。不明なら空欄にします。", isError: true)
    }

    var lines = ["件名: \(subject.isEmpty ? "（なし）" : subject)"]
    if !recipients.isEmpty { lines.append("宛先: \(recipients.joined(separator: ", "))") }
    lines.append(String(body.prefix(160)))
    guard let stepID = await approve(
      tool: .draftEmail,
      title: "メールの下書きを端末に保存",
      lines: lines,
      confirmTitle: "開く",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    var draft = MailDraft(recipients: recipients, subject: subject, body: body, cc: cc, bcc: bcc)
    draft.workspaceID = currentTeamID; draft.personIDs = aiPersonScopeID.map { [$0] } ?? []
    draft.sourceMessageID = messageID; draft.recordIDs = agentMessage(messageID)?.sources.map(\.meetingID) ?? []
    let projects = Set(draft.recordIDs.compactMap { meeting(id: $0)?.spaceID })
    draft.projectID = projects.count == 1 ? projects.first : nil
    guard saveMailDraft(draft) else {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "下書きを保存できませんでした")
      return AgentToolOutcome(text: "下書きの保存に失敗しました。送信していません。", isError: true)
    }
    pendingMailDraft = draft
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
    guard RecordAccessPolicy.allows(meeting.effectivePrivacy, purpose: .cloudAI),
          agentPluginPolicies[messageID].map({ !$0.limitsRecordReads || $0.recordIDs.contains(id) }) ?? true else {
      return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
    }
    let credential = KeychainStore.string(forKey: "integration.notion")
    let pageID = UserDefaults.standard.string(forKey: "memora.notionPageID")
    guard let stepID = await approve(
      tool: .saveToNotion,
      title: "Notionに保存",
      lines: [meeting.displayTitle, "この記録と送信を許可した関連タスクをNotionへ送ります。", "外部処理の料金は未確認です。今回の保存だけを許可します。"],
      confirmTitle: "保存",
      messageID: messageID
    ) else {
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      return Self.declinedOutcome
    }
    guard integrationIsEnabled("notion"), self.meeting(id: meeting.id) == meeting,
          credential == KeychainStore.string(forKey: "integration.notion"),
          pageID == UserDefaults.standard.string(forKey: "memora.notionPageID") else {
      return AgentToolOutcome(text: "記録または接続設定が変わったため、送信を止めました。内容を確認して再度依頼してください。", isError: true)
    }
    do {
      let safeTasks = permittedTasks(for: .cloudAI, scope: scope).filter { $0.meetingID == meeting.id }
      let outcome = try await NotionService.save(meeting: meeting, tasks: safeTasks)
      finishAgentStep(stepID, on: messageID, state: .done, detail: meeting.displayTitle)
      return AgentToolOutcome(text: "Notionに保存しました。\(outcome.pageURL?.absoluteString ?? "")")
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "保存できませんでした")
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      if let failure = error as? NotionService.Failure, case .http(let code) = failure {
        return AgentToolOutcome(text: ExternalToolFailure.http(code).localizedDescription, isError: true)
      }
      if let partial = error as? NotionService.PartialPageFailure {
        return AgentToolOutcome(text: "ページは作成されましたが、一部の内容を追加できませんでした。自動再作成はしません。" + (partial.pageURL.map { "ページ: " + $0.absoluteString } ?? ""), isError: true)
      }
      return AgentToolOutcome(text: "Notionへの保存結果を確認できませんでした。サービス側でページを確認してください。自動再作成はしません。", isError: true)
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
    var line = "- id=\(task.id.uuidString) \(task.isCompleted ? "[完了] " : "")\(task.title)"
    if !task.detail.isEmpty { line += " 説明: \(task.detail.prefix(500))" }
    if !task.isCompleted { line += " 状態: \(task.progress.label)" }
    if let workDate = task.workDate { line += " 取り組む日: \(agentDate(workDate))" }
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
