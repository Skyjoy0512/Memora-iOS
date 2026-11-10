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
    if let policy = agentPluginPolicies[messageID] {
      guard personPolicyIsCurrent(policy) else {
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
      let query = aiMessages.first(where: { $0.id == messageID })?.traceQuery ?? ""
      return await readAgentSourceExcerpt(id, messageID: messageID, compact: compact, automatic: automaticAccess, query: query)
    }
    if call.tool == .searchRecords, !automaticAccess {
      let lines = await searchAgentProjectSources(query: call.string("query"), messageID: messageID, compact: compact)
      if let outcome = automaticRecordTool(call, messageID: messageID, purpose: compact ? .onDeviceAI : .cloudAI, scope: scope) {
        return .init(text: ([outcome.text] + lines).joined(separator: "\n"), isError: outcome.isError && lines.isEmpty)
      }
    }
    if call.tool == .searchEmail || call.tool == .readEmail {
      guard !automaticAccess else {
        return AgentToolOutcome(text: "料金未確認のメール取得は自動処理では実行できません。チャットから明示的に依頼してください。", isError: true)
      }
      return await gmailReadTool(call, messageID: messageID, compact: compact, service: .shared)
    }
    if compact, agentPluginPolicies[messageID]?.limitsRecordReads == true,
       let outcome = automaticRecordTool(call, messageID: messageID, purpose: .onDeviceAI, scope: scope) { return outcome }
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
      return await saveToNotionTool(call, messageID: messageID, scope: scope, environment: .live)
    case .saveMemory:
      return await saveMemoryTool(call, messageID: messageID)
    case .searchEmail:
      return AgentToolOutcome(text: "メール取得を停止しました。", isError: true)
    case .readEmail:
      return AgentToolOutcome(text: "メール取得を停止しました。", isError: true)
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
    return AgentToolOutcome(text: stored ? "覚えました。" : "すでに覚えている内容です。", dataChange: stored ? .committed : .none)
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

    recordArtifactReads(found.map { .meeting($0.id) } + entries.map { .journal($0.id) }, messageID: messageID)

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
      recordArtifactReads([.meeting(meeting.id)] + tasks(forMeeting: meeting.id).map { .task($0.id) }, messageID: messageID)
      let text = compact ? compactAgentText(of: meeting) : agentText(of: meeting)
      return AgentToolOutcome(text: text + "\n" + AnswerSourceCitation.marker(for: .record(.meeting(meeting.id))))
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
      recordArtifactReads([.journal(entry.id)], messageID: messageID)
      return AgentToolOutcome(text: text + " " + AnswerSourceCitation.marker(for: .record(.journal(entry.id))) + "\n\(entry.summary)")
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
    recordArtifactReads(visible.map { .task($0.id) }, messageID: messageID)
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

  // MARK: - Changing

  private func createDocumentTool(_ call: AgentToolCall, tool: AgentTool, messageID: UUID) async -> AgentToolOutcome {
    guard let message = agentMessage(messageID) else { return Self.declinedOutcome }
    let workspaceID = currentTeamID
    let provenance = artifactProvenance(for: message)
    let title = call.string("title")
    let projectID = UUID(uuidString: call.string("project_id")).flatMap { space(id: $0)?.id }
    var document = MemoraDocument(
      title: title,
      kind: tool == .createSlides ? .slides : .document,
      spaceID: projectID
    )
    document.provenance = provenance
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
      do {
        let input = call.objects("slides")
        guard input.count <= 65 else { return AgentToolOutcome(text: "一度の作成は65枚までです。", isError: true) }
        document.slides = try input.map { try PresentationToolInput.slide($0) }
        if !call.string("plan_json").isEmpty {
          document.presentationPlan = try PresentationToolInput.plan(call.string("plan_json"), slides: document.slides)
        }
      } catch {
        return AgentToolOutcome(text: "スライドを保存する前に修正してください: \(error.localizedDescription)", isError: true)
      }
      guard !document.slides.isEmpty else {
        return AgentToolOutcome(text: "slidesが空です。スライドを1枚以上書いてください。", isError: true)
      }
      if let evidence = agentPresentationEvidence[messageID] {
        document.presentationEvidence = evidence
        lines.append("根拠: 候補\(evidence.investigation.consideredSources)件 / 採用\(evidence.investigation.includedSources)件 / 決定\(evidence.decisions.count)件")
        if !evidence.gaps.isEmpty { lines.append("不足: \(evidence.gaps.joined(separator: " / "))") }
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
      if document.kind == .document {
        var citationMessage = message
        citationMessage.text = document.markdown
        document.markdown = AIAnswerDocumentBuilder.make(message: citationMessage, question: document.title, provenance: provenance).markdown
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
    guard artifactCreationIsCurrent(messageID: messageID, workspaceID: workspaceID, provenance: provenance),
          pluginCallIsPermitted(call, messageID: messageID) else {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "参照情報または権限が変更されました")
      return AgentToolOutcome(text: "参照情報または権限が変わったため、資料作成を止めました。", isError: true)
    }

    do {
      document = try await prepareDocumentArtifact(document, call: call)
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "ファイルを作成できませんでした")
      return AgentToolOutcome(text: error.localizedDescription, isError: true)
    }
    guard artifactCreationIsCurrent(messageID: messageID, workspaceID: workspaceID, provenance: provenance),
          pluginCallIsPermitted(call, messageID: messageID), addDocument(document) else {
      if let name = document.artifactFileReference { await ProjectSourceFiles.shared.remove([name]) }
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "保存できませんでした")
      return AgentToolOutcome(text: "保存に失敗しました。", isError: true)
    }
    updateAgentMessage(messageID) { $0.documentIDs.append(document.id) }
    finishAgentStep(stepID, on: messageID, state: .done, detail: document.displayTitle)
    return AgentToolOutcome(text: "\(document.artifactFormat ?? kindLabel)ファイルを生成・再読込検証し、資料として保存しました。id=\(document.id.uuidString)。最終フォント・改ページ・文字あふれはプレビューで確認してください。", dataChange: .committed)
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
    return AgentToolOutcome(text: "プロジェクトを作成しました。id=\(id.uuidString)", dataChange: .committed)
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

    let changesProject = records.contains { meeting(id: $0.id)?.spaceID != space.id }
    guard moveMeetings(Set(records.map(\.id)), to: space.id) else {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "移動を保存できませんでした")
      return AgentToolOutcome(text: "移動を保存できませんでした。元のプロジェクトは変更していません。", isError: true)
    }
    finishAgentStep(stepID, on: messageID, state: .done, detail: space.name)
    return AgentToolOutcome(text: "\(records.count)件を移動しました。", dataChange: changesProject ? .committed : .none)
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
      ? AgentToolOutcome(text: "ジャーナルに追加しました。", dataChange: .committed)
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
      return AgentToolOutcome(text: "カレンダーに追加しました。", dataChange: .committed)
    } catch CalendarService.AddEventError.accessDenied {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "カレンダーへのアクセスが許可されていません")
      return AgentToolOutcome(text: "カレンダーへのアクセスが許可されていないため追加できませんでした。設定アプリで許可するよう伝えてください。", isError: true)
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "追加できませんでした")
      return AgentToolOutcome(text: "カレンダーに追加できませんでした。", isError: true)
    }
  }

  // MARK: - Helpers

  /// Shows the step and the approval card. Returns the step's id when approved,
  /// so the caller can settle it, or nil when declined.
  func approve(
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

  static let declinedOutcome = AgentToolOutcome(
    text: "利用者がこの操作を承認しませんでした。同じ操作を繰り返さず、必要なら理由を尋ねてください。"
  )

  static func agentTaskLine(_ task: MemoraTask) -> String {
    var line = "- id=\(task.id.uuidString) \(task.isCompleted ? "[完了] " : "")\(task.title) \(AnswerSourceCitation.marker(for: .record(.task(task.id))))"
    if !task.detail.isEmpty { line += " 説明: \(task.detail.prefix(500))" }
    if !task.isCompleted { line += " 状態: \(task.progress.label)" }
    if let workDate = task.workDate { line += " 取り組む日: \(agentDate(workDate))" }
    if let assignee = task.assignee, !assignee.isEmpty { line += " 担当: \(assignee)" }
    if let due = task.dueDate { line += " 期限: \(agentDate(due))" }
    return line
  }

  static func agentDate(_ date: Date) -> String {
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
