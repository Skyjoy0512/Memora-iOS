import Foundation

// Ask AI: the chat transcript and answers grounded in relevant records.
extension MemoraModel {

  /// Navigation never starts a conversation. Only the explicit new-chat action does.
  func didChangeTab(from previous: RootTab) {
    if previous == .askAI, selectedTab != .askAI {
      persistActiveAIConversation()
    }
  }

  func startNewAIChat() {
    // An agent waiting on an approval card would never resume otherwise.
    resolveAgentApproval(false)
    resolveAgentQuestions(nil)
    aiChatTask?.cancel()
    aiChatTask = nil
    aiChatRequestID = nil
    aiMessages = []
    agentToolCallCounts = [:]
    agentPluginPolicies = [:]
    agentBlockedExternalTools = [:]
    isAIChatResponding = false
    persistActiveAIConversation()
  }

  /// Stops the answer being written. The request is let go first, so a result
  /// that still arrives is treated as stale and never fills the message in.
  func stopAIChat() {
    guard isAIChatResponding else { return }
    aiChatRequestID = nil
    aiChatTask?.cancel()
    aiChatTask = nil
    // An agent paused on an approval card is declined, so it does not resume.
    resolveAgentApproval(false)
    resolveAgentQuestions(nil)
    if let index = aiMessages.lastIndex(where: { $0.role == .assistant && $0.isThinking }) {
      settleTraceSteps(at: index, as: .declined)
      aiMessages[index].isThinking = false
      aiMessages[index].finishedAt = .now
      if aiMessages[index].text.isEmpty {
        aiMessages[index].text = "回答を停止しました。"
      } else {
        aiMessages[index].text = NativeAIInterface.response(aiMessages[index].text).markdown
          + "\n\n回答を停止しました。ここまでの回答は未完了です。"
      }
    }
    isAIChatResponding = false
  }

  /// Finishes whatever trace steps were still running when the reply settled.
  func settleTraceSteps(at index: Int, as state: AgentStep.State) {
    for step in aiMessages[index].agentSteps.indices where aiMessages[index].agentSteps[step].state == .running {
      aiMessages[index].agentSteps[step].state = state
    }
  }

  /// Whether the reply can be asked for again: the latest one, as long as it
  /// changed nothing — re-running it could repeat a change already made.
  func canRetryAIAnswer(_ messageID: UUID) -> Bool {
    guard !isAIChatResponding,
          let last = aiMessages.last, last.id == messageID, last.role == .assistant,
          !last.didChangeData, last.residentName == nil else { return false }
    return aiMessages.dropLast().last?.role == .user
  }

  /// Asks the latest question again, replacing its answer.
  func retryAIAnswer(_ messageID: UUID) {
    guard canRetryAIAnswer(messageID) else { return }
    let question = aiMessages[aiMessages.count - 2].text
    let plugins = aiMessages[aiMessages.count - 2].pluginIDs
    aiMessages.removeLast(2)
    sendAIChat(question, pluginIDs: plugins)
  }

  /// Asks the chat a question. Returns false while an answer is already on its
  /// way, so the caller keeps the text instead of losing it to a refused send.
  @discardableResult
  func sendAIChat(_ question: String, attachment: AIAttachment? = nil, webSearchRequested: Bool = false, pluginIDs: [String] = []) -> Bool {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || attachment != nil, !isAIChatResponding else { return false }

    if !pluginIDs.isEmpty {
      let selected = AIPluginExecutionPolicy.selectionIDs(pluginIDs, webSearchRequested: webSearchRequested)
      return sendPluginChat(trimmed, pluginIDs: selected, attachment: attachment)
    }

    if attachment == nil {
      switch AIWebSearchIntent.route(trimmed, requested: webSearchRequested, previousQuery: latestChatWebQuery) {
      case .search(let query): return sendWebSearchChat(trimmed, query: query)
      case .needsTopic: return sendWebSearchChat(trimmed, query: nil)
      case .none: break
      }
    }

    // Asked plainly to remember something: it is kept before answering, and
    // the conversation says so, so it is never kept silently.
    let remembered = isAIMemoryEnabled ? Self.explicitMemory(in: trimmed) : nil
    let didRemember = remembered.map { addAIMemory($0, origin: .told) } ?? false

    if AIEngineService.effectiveEngine(askAIConfiguration.engine) == .cloud, !askAIConfiguration.llm.supportsToolCalling {
      if !didRemember, Self.shouldRunAsAgent(trimmed, engine: .foundation, hasAttachment: attachment != nil) {
        aiMessages.append(AIChatMessage(role: .user, text: trimmed))
        aiMessages.append(AIChatMessage(role: .assistant, text: "このモデルのツール呼び出しはオフです。対応モデルを設定 → AI整理で登録して有効にすると、連携サービスや書き込み操作を使えます。通常の質問には回答できます。"))
        return true
      }
      return sendGroundedAnswer(trimmed, attachment: attachment, remembered: didRemember ? remembered : nil)
    }

    // One assistant, no mode to choose. A cloud model runs as the agent and
    // decides for itself whether to answer or to do the work. The on-device
    // model is unreliable with tools, so it gets the agent only for a request
    // to do something; a question goes through the grounded answer, which
    // finds the records first and answers from them.
    if Self.shouldRunAsAgent(trimmed, engine: askAIConfiguration.engine, hasAttachment: attachment != nil) {
      let sent = sendAgentChat(question, attachment: attachment)
      if sent, didRemember, let remembered {
        insertMemoryNote(remembered)
      }
      return sent
    }
    return sendGroundedAnswer(trimmed, attachment: attachment, remembered: didRemember ? remembered : nil)
  }

  /// Whether a request goes to the agent: always on a cloud model; on the
  /// device only when it asks for something to be done.
  static func shouldRunAsAgent(_ request: String, engine: AIEngine, hasAttachment: Bool) -> Bool {
    // The agent cannot read attachments yet; the grounded answer can.
    guard !hasAttachment else { return false }
    if AIEngineService.effectiveEngine(engine) == .cloud { return true }
    let actions = [
      "下書き", "作って", "作成", "追加", "登録", "入れて", "保存", "送って", "送信", "メール",
      "予定", "カレンダー", "タスクに", "資料", "スライド", "覚えて", "移動", "Notion",
      "集計", "何件", "何時間", "振り返り", "振り返って", "Web検索", "ウェブ検索", "Deep Research", "deep research", "ディープリサーチ"
    ]
    return actions.contains { request.contains($0) }
  }

  /// A question answered from the records found for it, in one pass.
  private func sendGroundedAnswer(_ trimmed: String, attachment: AIAttachment?, remembered: String?) -> Bool {
    let didRemember = remembered != nil
    let configuration = askAIConfiguration
    let engine = configuration.engine
    let llm = configuration.llm
    let scope = AIChatScope.all
    let history = aiConversationContext()
    let requestID = UUID()
    aiChatRequestID = requestID

    aiMessages.append(AIChatMessage(role: .user, text: trimmed))
    if didRemember, let remembered {
      aiMessages.append(Self.memoryNote(remembered))
    }
    let personal = personalContext(
      for: trimmed,
      budget: AIEngineService.contextCharacterLimit(for: engine) / 6
    )
    // The trace shows the record search that really runs, and its results.
    var placeholder = AIChatMessage(role: .assistant, text: "", isThinking: true)
    // The question as asked, on one line; the internal search words are
    // fragments that would read as noise.
    let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
    placeholder.traceQuery = oneLine.isEmpty ? nil : String(oneLine.prefix(60))
    aiMessages.append(placeholder)
    isAIChatResponding = true

    aiChatTask?.cancel()
    aiChatTask = Task { [weak self] in
      guard let self else { return }
      let allowedMeetings = Self.meetings(in: scope, from: self.meetings)
      let outcome = await self.answer(
        request: AIQuestionRequest(question: trimmed, scope: .global, attachment: attachment),
        scopeLabel: scope.scopeLabel,
        allowedMeetings: allowedMeetings,
        tasks: Self.openTasks(in: scope, from: self.tasks, meetings: allowedMeetings),
        history: history,
        personal: personal,
        engine: engine,
        llm: llm,
        onContextReady: { [weak self] sources in
          guard let self, self.aiChatRequestID == requestID else { return }
          self.updateAgentMessage(placeholder.id) { message in
            message.sources = sources
            message.searchFinished = true
          }
        },
        onText: { [weak self] text in
          guard let self, !Task.isCancelled, self.aiChatRequestID == requestID else { return }
          self.updateAgentMessage(placeholder.id) { $0.text = text }
        }
      )

      // A newer chat or question owns the screen now; this result is stale, and
      // only the owner clears the responding state.
      guard self.aiChatRequestID == requestID else { return }
      defer {
        self.isAIChatResponding = false
        self.aiChatTask = nil
        self.aiChatRequestID = nil
      }
      guard !Task.isCancelled else { return }

      // Tell the person what was left out before answering, so a send that
      // carried nothing never looks successful.
      if let unsupported = outcome.unsupportedAttachmentNote,
         let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
        self.aiMessages.insert(AIChatMessage(role: .assistant, text: unsupported), at: index)
      }
      // Say when the context had to be trimmed, so a short answer is not taken
      // for a complete one.
      if let note = outcome.contextNote,
         let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
        self.aiMessages.insert(AIChatMessage(role: .assistant, text: note), at: index)
      }

      switch outcome.result {
      case .answer(let text):
        if let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
          self.aiMessages[index].text = text
          self.aiMessages[index].details = outcome.details
          self.aiMessages[index].isThinking = false
          self.aiMessages[index].finishedAt = .now
          // Only records that were actually sent are offered as grounds.
          self.aiMessages[index].sources = outcome.sources
          self.settleTraceSteps(at: index, as: .done)
        }
        self.saveAIExchange(
          question: outcome.question,
          answer: text,
          scopeLabel: outcome.scopeLabel,
          engineLabel: outcome.details.engineLabel,
          modelLabel: outcome.details.modelLabel
        )

      case .failure(let failure):
        // Cancellation is not a failure to report; the newer request answers.
        guard failure != .cancelled else { return }
        if let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
          self.aiMessages[index].text = failure.message
          self.aiMessages[index].details = outcome.details
          self.aiMessages[index].isThinking = false
          self.aiMessages[index].finishedAt = .now
          // A failed answer rests on nothing, so it offers no records.
          self.aiMessages[index].sources = []
          self.aiMessages[index].searchFinished = false
          self.settleTraceSteps(at: index, as: .failed)
        }
      }
    }

    return true
  }


  /// Answers a question with the chosen engine, using only the records the range
  /// allows. Both the chat and the focused question screen come through here, so
  /// the range, the attachment handling, and the grounds shown are decided once.
  func answer(
    request: AIQuestionRequest,
    scopeLabel: String,
    allowedMeetings: [Meeting],
    tasks scopedTasks: [MemoraTask],
    history: String,
    personal: String = "",
    engine: AIEngine,
    llm: LLMSelection,
    onContextReady: (([AIChatSource]) -> Void)? = nil,
    onText: (@MainActor (String) -> Void)? = nil
  ) async -> AIAnswerOutcome {
    let workspaceID = currentTeamID
    let cloud = AIEngineService.effectiveEngine(engine) == .cloud
    let memoryFingerprint = request.scope == .global ? cloudMemoryFingerprint : nil
    let scopedMeetings = Self.meetings(in: request.scope, from: allowedMeetings)
    let permitted = scopedMeetings.filter { !cloud || allowsRecordAccess($0.id, purpose: .cloudAI) }
    let recordIDs = Set(permitted.map(\.id))
    let permittedTasks = scopedTasks.filter {
      request.scope.includesTask(parentRecordID: $0.meetingID, recordIDs: recordIDs)
        && (!cloud || allowsTaskAccess($0, purpose: .cloudAI))
    }
    let attachmentContent: PreparedAIAttachment?
    if let attachment = request.attachment { attachmentContent = await AIAttachmentText.prepare(attachment) }
    else { attachmentContent = nil }

    func contextAvailable() -> Bool {
      guard !isRestoring, !isStoreProtected, currentTeamID == workspaceID else { return false }
      if case .file(let id) = request.scope, meeting(id: id) == nil { return false }
      if case .space(let id) = request.scope, space(id: id) == nil { return false }
      return (memoryFingerprint == nil || memoryFingerprint == cloudMemoryFingerprint)
        && permitted.allSatisfy { record in
          meeting(id: record.id) == record
            && request.scope.includes(recordID: record.id, projectID: record.spaceID)
            && (!cloud || allowsRecordAccess(record.id, purpose: .cloudAI))
        }
        && permittedTasks.allSatisfy { task in
          self.task(id: task.id) == task && (!cloud || allowsTaskAccess(task, purpose: .cloudAI))
        }
    }

    func buildContent(limit: Int) -> AIRequestContent {
      Self.requestContent(for: request, scopeLabel: scopeLabel,
        allowedMeetings: permitted, tasks: permittedTasks,
        history: request.scope == .global && !cloud ? history : "",
        personal: request.scope == .global ? (cloud ? personalContext(for: request.effectiveQuestion,
          budget: limit / 6, includesHistory: false) : personal) : "",
        characterLimit: limit, attachmentContent: attachmentContent)
    }

    let scopedRecord: Meeting?
    if case .file = request.scope, cloud, llm.supportsToolCalling, !llm.isMemoraIntelligence,
       permitted.count == 1, [.searchRecords, .readRecord, .listTasks].contains(where: { enabledAgentTools.contains($0) }) {
      scopedRecord = permitted.first
    } else { scopedRecord = nil }
    var content = buildContent(limit: scopedRecord == nil ? AIEngineService.contextCharacterLimit(for: engine) : 28_000)
    func outcome(_ result: AIAnswerResult) -> AIAnswerOutcome {
      AIAnswerOutcome(question: content.question, scopeLabel: scopeLabel, result: result,
        sources: result.text == nil ? [] : content.sources,
        details: AIAnswerDetails(scopeLabel: scopeLabel,
          engineLabel: AIEngineService.effectiveEngine(engine).label,
          modelLabel: AIEngineService.modelLabel(engine: engine, llm: llm),
          sourceCount: result.text == nil ? 0 : content.sources.count, generatedAt: .now),
        unsupportedAttachmentNote: content.unsupportedAttachmentNote, contextNote: content.contextNote)
    }
    guard !Task.isCancelled else { return outcome(.failure(.cancelled)) }
    // A denied record's title in scopeLabel must not reach the provider either.
    if cloud, case .file(let id) = request.scope, !allowsRecordAccess(id, purpose: .cloudAI) {
      return outcome(.failure(.recordAccessDenied))
    }
    // File reading may yield to edits, workspace switching or privacy changes.
    guard contextAvailable() else { return outcome(.failure(.contextChanged)) }
    guard content.unsupportedAttachmentNote == nil else { return outcome(.failure(.attachmentNotAnalysed)) }
    onContextReady?(content.sources)
    // The context callback can also change the model before the first network request.
    guard !Task.isCancelled, contextAvailable() else {
      return outcome(.failure(Task.isCancelled ? .cancelled : .contextChanged))
    }
    let safeText: (@MainActor (String) -> Void)? = onText.map { callback in { text in
        guard !Task.isCancelled, contextAvailable() else { return }
        callback(text)
      } }
    var result: AIAnswerResult
    if let scopedRecord {
      let answer = await answerRecordAgent(content: content, record: scopedRecord, scopedTasks: permittedTasks,
        llm: llm, isCurrent: contextAvailable, onText: safeText)
      result = answer.result
      content.sources = answer.sources
    } else {
      result = await AIEngineService.answer(engine: engine, llm: llm,
        question: content.question, scopeLabel: scopeLabel, context: content.context,
        history: content.history, onText: safeText)
    }

    guard !Task.isCancelled else { return outcome(.failure(.cancelled)) }
    guard contextAvailable() else { return outcome(.failure(.contextChanged)) }
    // A local retry reuses the same extracted attachment and the same verified records.
    if case .failure(.contextTooLarge) = result, !cloud {
      content = buildContent(limit: max(500, AIEngineService.contextCharacterLimit(for: engine) / 2))
      guard content.unsupportedAttachmentNote == nil else { return outcome(.failure(.attachmentNotAnalysed)) }
      onContextReady?(content.sources)
      guard !Task.isCancelled, contextAvailable() else {
        return outcome(.failure(Task.isCancelled ? .cancelled : .contextChanged))
      }
      result = await AIEngineService.answer(engine: engine, llm: llm,
        question: content.question, scopeLabel: scopeLabel, context: content.context, history: content.history)
    }
    if Task.isCancelled { result = .failure(.cancelled) }
    else if !contextAvailable() { result = .failure(.contextChanged) }
    return outcome(result)
  }

  /// Assembles what a request would send. Pure, so a test can check that records
  /// outside the requested range are absent without calling an engine.
  ///
  /// One record carries its whole transcript when it fits. A wider range, or one
  /// too large to send whole, is cut into ~800-character spans: the high-scoring
  /// spans are kept in time order up to the engine's limit, and at most eight
  /// records are described.
  static func requestContent(
    for request: AIQuestionRequest,
    scopeLabel: String,
    allowedMeetings: [Meeting],
    tasks: [MemoraTask],
    history: String = "",
    personal: String = "",
    characterLimit: Int = AIEngineService.defaultContextCharacterLimit,
    attachmentContent: PreparedAIAttachment? = nil,
    prioritizesPassages: Bool = false
  ) -> AIRequestContent {
    let question = request.effectiveQuestion
    let words = questionWords(in: question)

    // After the question, the budget is shared: the attachment may take at most
    // 40%, the recent exchanges at most 20%, and the records are guaranteed the
    // rest. What the first two do not use goes to the records, so a long
    // attachment can never crowd them out completely.
    let budgetAfterQuestion = max(0, characterLimit - question.count)
    let attachmentCap = budgetAfterQuestion * 2 / 5
    let historyCap = budgetAfterQuestion / 5
    var remaining = budgetAfterQuestion
    var notes: [String] = []

    // What Ask AI knows about the person comes first and takes at most a
    // sixth, so the records still get most of the room.
    let personalText = String(personal.prefix(budgetAfterQuestion / 6))
    remaining = max(0, remaining - personalText.count)

    var attachmentText = ""
    var unsupportedNote: String?
    if let attachment = request.attachment {
      if let attachmentContent, attachmentContent.matches(attachment),
         attachmentContent.failure == nil, let text = attachmentContent.text, !text.isEmpty {
        let label = "添付「\(attachment.name)」:\n"
        let allowance = max(0, min(remaining, attachmentCap) - label.count)
        let kept = String(text.prefix(allowance))
        if kept.count < text.count {
          notes.append("添付「\(attachment.name)」は長いため、先頭のみ送信しました。")
        }
        attachmentText = label + kept
        remaining = max(0, remaining - attachmentText.count)
        if let notice = attachmentContent.notice { notes.append(notice) }
        if kept.isEmpty { unsupportedNote = "添付の本文を送る余地がありません。質問を短くしてください。" }
      } else {
        let reason = attachmentContent?.matches(attachment) == true ? attachmentContent?.failure : nil
        unsupportedNote = "添付「\(attachment.name)」の内容は送信していません。\(reason ?? "本文の読み込みを確認できませんでした。")"
      }
    }

    var historyText = ""
    if !history.isEmpty, remaining > 0 {
      let allowance = min(remaining, historyCap)
      let kept = Self.trailingHistory(history, budget: allowance)
      if kept.count < history.count {
        notes.append("これまでのやりとりが長いため、新しい方を優先して送信しました。")
      }
      historyText = kept
      remaining = max(0, remaining - historyText.count)
    }

    let built: (context: String, sources: [AIChatSource])
    let scopedMeetings = meetings(in: request.scope, from: allowedMeetings)
    let recordIDs = Set(scopedMeetings.map(\.id))
    let scopedTasks = tasks.filter { request.scope.includesTask(parentRecordID: $0.meetingID, recordIDs: recordIDs) }
    switch request.scope {
    case .file:
      built = fileContext(meeting: scopedMeetings.first, words: words, characterLimit: remaining)
    case .space, .global:
      built = libraryContext(
        meetings: scopedMeetings,
        tasks: scopedTasks,
        words: words,
        characterLimit: remaining,
        prioritizesPassages: prioritizesPassages
      )
    }

    var context = built.context
    if !personalText.isEmpty {
      context = personalText + "\n\n" + context
    }
    if !attachmentText.isEmpty {
      context += "\n\n\(attachmentText)"
    }

    return AIRequestContent(
      question: question,
      scopeLabel: scopeLabel,
      context: context,
      history: historyText,
      sources: built.sources,
      unsupportedAttachmentNote: unsupportedNote,
      contextNote: notes.isEmpty ? nil : notes.joined(separator: "\n")
    )
  }

  /// The newest exchanges that fit the budget, kept whole where possible. A
  /// follow-up needs the turns just before it, so the start of the thread is what
  /// is dropped. An answer is multi-line, so exchanges are found from the
  /// "利用者:" / "回答:" turn starts rather than by counting lines. When even the
  /// latest exchange is too large, its question is kept whole and its answer is
  /// shortened with an ellipsis, so the newest question is never lost.
  static func trailingHistory(_ history: String, budget: Int) -> String {
    guard !history.isEmpty, budget > 0 else { return "" }
    if history.count <= budget { return history }

    let exchanges = historyExchanges(history)
    var kept: [[String]] = []
    var used = 0
    for exchange in exchanges.reversed() {
      let text = exchange.joined(separator: "\n")
      let cost = text.count + (kept.isEmpty ? 0 : 1)
      if used + cost <= budget {
        kept.append(exchange)
        used += cost
      } else if kept.isEmpty {
        kept.append(shorten(exchange, budget: budget))
        break
      } else {
        break
      }
    }
    return kept.reversed().map { $0.joined(separator: "\n") }.joined(separator: "\n")
  }

  /// Splits the thread into exchanges, each an array of its lines. A new exchange
  /// begins at a user turn, so multi-line answers stay with their question.
  private static func historyExchanges(_ history: String) -> [[String]] {
    var exchanges: [[String]] = []
    var current: [String] = []
    for line in history.components(separatedBy: "\n") {
      if line.hasPrefix("利用者: "), !current.isEmpty {
        exchanges.append(current)
        current = []
      }
      current.append(line)
    }
    if !current.isEmpty {
      exchanges.append(current)
    }
    return exchanges
  }

  /// Keeps an exchange's question whole and trims its answer to what fits.
  private static func shorten(_ exchange: [String], budget: Int) -> [String] {
    let answerStart = exchange.firstIndex { $0.hasPrefix("回答: ") } ?? exchange.count
    let question = exchange[..<answerStart].joined(separator: "\n")
    let answer = exchange[answerStart...].joined(separator: "\n")
    guard !answer.isEmpty else {
      return [String(question.prefix(budget))]
    }
    // One character is reserved for the newline between the two parts.
    let available = budget - question.count - 1
    guard available > 1 else {
      return [String(question.prefix(budget))]
    }
    return [question, String(answer.prefix(available - 1)) + "…"]
  }

  /// One record's own context: its digest plus as much of the transcript as fits.
  private static func fileContext(
    meeting: Meeting?,
    words: [String],
    characterLimit: Int
  ) -> (String, [AIChatSource]) {
    guard let meeting else { return ("", []) }

    var lines: [String] = [
      "【資料1】会議: \(meeting.displayTitle)",
      "日付: \(meeting.createdAt.formatted(date: .numeric, time: .omitted))"
    ]
    if !meeting.summary.isEmpty {
      lines.append("要約: \(meeting.summary)")
    }
    lines.append(contentsOf: meeting.decisions.prefix(8).map { "決定: \($0)" })
    lines.append(contentsOf: meeting.openQuestions.prefix(8).map { "未決: \($0)" })

    // The transcript takes what is left after the digest, so the whole context
    // stays within the engine's budget.
    let prefix = lines.joined(separator: "\n")
    let marker = "\n文字起こし:"
    let budget = max(0, characterLimit - prefix.count - marker.count)
    let transcript = transcriptBlock(meeting, words: words, characterLimit: budget)
    if !transcript.text.isEmpty {
      lines.append("文字起こし:")
      lines.append(transcript.text)
    }

    let source = AIChatSource(
      meetingID: meeting.id,
      title: meeting.displayTitle,
      excerpts: transcript.excerpts
    )
    let joined = lines.joined(separator: "\n")
    let bounded = joined.count > characterLimit ? String(joined.prefix(characterLimit)) : joined
    return (bounded, [source])
  }

  /// A wider range: each record's digest and best spans, up to eight records and
  /// the engine's character limit.
  private static func libraryContext(
    meetings: [Meeting],
    tasks: [MemoraTask],
    words: [String],
    characterLimit: Int,
    prioritizesPassages: Bool = false
  ) -> (String, [AIChatSource]) {
    let ranked = rank(meetings: meetings, words: words, tasks: tasks).prefix(8)
    var blocks: [String] = []
    var sources: [AIChatSource] = []
    var used = 0

    // A task with no record is reachable only from the whole-library range. It
    // shares the same budget as everything else.
    let looseTasks = tasks.filter { !$0.isCompleted && $0.meetingID == nil }
    if !looseTasks.isEmpty, characterLimit > 0 {
      let block = String(
        ("未完了のタスク:\n" + looseTasks.map { "- \($0.title)" }.joined(separator: "\n"))
          .prefix(characterLimit)
      )
      used += block.count
      blocks.append(block)
    }

    for meeting in ranked {
      var lines: [String] = [
        // Numbered so an answer can cite it; only these numbers become chips.
        "【資料\(sources.count + 1)】会議: \(meeting.displayTitle)",
        "日付: \(meeting.createdAt.formatted(date: .numeric, time: .omitted))"
      ]
      if !meeting.summary.isEmpty {
        let summary = prioritizesPassages ? String(meeting.summary.prefix(min(1_200, max(0, characterLimit / 3)))) : meeting.summary
        lines.append("要約: \(summary)")
      }
      lines.append(contentsOf: meeting.decisions.prefix(5).map { "決定: \($0)" })
      lines.append(contentsOf: meeting.openQuestions.prefix(5).map { "未決: \($0)" })
      lines.append(contentsOf: tasks
        .filter { $0.meetingID == meeting.id && !$0.isCompleted }
        .prefix(5)
        .map { "タスク: \($0.title)" })

      let spans = scoredSpans(of: meeting, words: words)
      let rankedSpans = spans
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        .prefix(3)
      let best: [ScoredSpan]
      if prioritizesPassages {
        var available = max(0, characterLimit - used - lines.joined(separator: "\n").count - 2)
        var selected: [ScoredSpan] = []
        // Fit the strongest evidence first, then restore time order within what will actually be sent.
        for span in rankedSpans {
          let cost = span.text.count + 5
          if cost <= available { selected.append(span); available -= cost }
          else if selected.isEmpty, available > 35 {
            var clipped = span
            clipped.text = RelevantTextWindow.text(span.text, matching: words, maximumCharacters: available - 5)
            selected.append(clipped)
            available = 0
          }
        }
        best = selected.sorted { $0.start < $1.start }
      } else { best = rankedSpans.sorted { $0.start < $1.start } }
      for span in best {
        lines.append("発言:")
        lines.append(span.text)
      }

      var block = lines.joined(separator: "\n")
      let remainingBudget = max(0, characterLimit - used)
      if block.count > remainingBudget {
        // The first record is always sent, trimmed to what is left, so a range
        // with one huge record still carries something.
        guard blocks.isEmpty, remainingBudget > 0 else { break }
        block = String(block.prefix(remainingBudget))
      }
      used += block.count + 2
      blocks.append(block)
      sources.append(
        AIChatSource(
          meetingID: meeting.id,
          title: meeting.displayTitle,
          excerpts: best.map { AIChatSource.Excerpt(text: snippet($0.text), start: $0.start) }
        )
      )
    }

    let joined = blocks.joined(separator: "\n\n")
    return (String(joined.prefix(characterLimit)), Array(sources))
  }

  /// The transcript as sent: whole when it fits, otherwise the high-scoring spans
  /// in time order. Also returns the excerpts shown as grounds.
  private static func transcriptBlock(
    _ meeting: Meeting,
    words: [String],
    characterLimit: Int
  ) -> (text: String, excerpts: [AIChatSource.Excerpt]) {
    guard !meeting.transcript.isEmpty else { return ("", []) }

    let full = meeting.transcript
      .map { transcriptLine($0, showsSpeaker: meeting.hasSpeakerSeparation) }
      .joined(separator: "\n")
    if full.count <= characterLimit {
      return (full, topExcerpts(meeting.transcript, words: words))
    }

    let spans = scoredSpans(of: meeting, words: words)
    let scored = spans.filter { $0.score > 0 }.sorted { $0.score > $1.score }.prefix(8)
    let hasMatches = !scored.isEmpty
    let chosen = hasMatches ? Array(scored) : Array(spans.sorted { $0.start < $1.start }.prefix(3))
    let ordered = chosen.sorted { $0.start < $1.start }

    var text = ""
    var used: [ScoredSpan] = []
    for span in ordered {
      let addition = text.isEmpty ? span.text : "\n" + span.text
      if text.count + addition.count > characterLimit { break }
      text += addition
      used.append(span)
    }

    // Only matched lines are shown as grounds; an unmatched question gets none
    // rather than the transcript's opening lines presented as if they matched.
    let excerpts = hasMatches
      ? used.filter { $0.score > 0 }.prefix(3).map {
        AIChatSource.Excerpt(text: snippet($0.text), start: $0.start)
      }
      : []
    return (text, excerpts)
  }

  /// A transcript segment as one sent line, with its time (and speaker when the
  /// record separates them).
  private static func transcriptLine(_ segment: TranscriptSegment, showsSpeaker: Bool) -> String {
    let stamp = MemoraFormat.duration(segment.timestamp)
    if showsSpeaker, !segment.speaker.isEmpty {
      return "[\(stamp)] \(segment.speaker): \(segment.text)"
    }
    return "[\(stamp)] \(segment.text)"
  }

  /// Transcript lines bundled into spans of about `maxLength` characters, each
  /// scored by how many of the question's terms it holds.
  private static func scoredSpans(of meeting: Meeting, words: [String]) -> [ScoredSpan] {
    let showsSpeaker = meeting.hasSpeakerSeparation
    var spans: [ScoredSpan] = []
    var current: [TranscriptSegment] = []
    var length = 0

    func flush() {
      guard let first = current.first else { return }
      let text = current
        .map { transcriptLine($0, showsSpeaker: showsSpeaker) }
        .joined(separator: "\n")
      let score = words.reduce(0) { total, word in
        total + (text.localizedCaseInsensitiveContains(word) ? 1 : 0)
      }
      spans.append(ScoredSpan(start: first.timestamp, text: text, score: score))
      current = []
      length = 0
    }

    for segment in meeting.transcript {
      let lineLength = segment.text.count + 18
      if length > 0, length + lineLength > ScoredSpan.maxLength { flush() }
      current.append(segment)
      length += lineLength
    }
    flush()
    return spans
  }

  /// Up to three stored lines that match the question, in time order. When no
  /// line matches, there are no grounds to show; the opening lines are not shown
  /// as though they did.
  private static func topExcerpts(
    _ transcript: [TranscriptSegment],
    words: [String]
  ) -> [AIChatSource.Excerpt] {
    guard !words.isEmpty else { return [] }
    let matched = transcript
      .map { segment -> (segment: TranscriptSegment, score: Int) in
        (segment, words.filter { segment.text.localizedCaseInsensitiveContains($0) }.count)
      }
      .filter { $0.score > 0 }
      .sorted { $0.score > $1.score }
      .prefix(3)
      .map(\.segment)
      .sorted { $0.timestamp < $1.timestamp }
    return matched.map { AIChatSource.Excerpt(text: snippet($0.text), start: $0.timestamp) }
  }

  /// A stored excerpt as shown: the sentence shortened, never rewritten.
  private static func snippet(_ text: String) -> String {
    text.count > 120 ? String(text.prefix(120)) + "…" : text
  }

  /// The records worth sending, ranked by the question's terms: a title match
  /// counts most, a decision, open question or task next, and body text least.
  static func rank(meetings: [Meeting], words: [String], tasks: [MemoraTask] = []) -> [Meeting] {
    MeetingRanking.rank(meetings: meetings, words: words, tasks: tasks)
  }

  /// The text a record is searched by, without any cache, so the same result can
  /// be produced outside the model.
  static func searchableText(of meeting: Meeting) -> String {
    ([meeting.title, meeting.notes, meeting.summary]
      + meeting.decisions
      + meeting.openQuestions
      + meeting.keyPoints
      + meeting.transcript.map(\.text))
      .joined(separator: "\n")
  }

  /// The exchanges so far in this chat, so a follow-up question has the thread
  /// it belongs to.
  func aiConversationContext() -> String {
    let settled = aiMessages.filter { $0.role != .assistant || !$0.isThinking }
    let turns = settled.suffix(6)
    return turns
      .map { message in
        "\(message.role == .user ? "利用者" : "回答"): \(message.text)"
      }
      .joined(separator: "\n")
  }

  /// The records a question reaches: those whose own text contains its words,
  /// ranked by how many of them match, then by recency. A question with nothing
  /// to go on falls back to the most recent records. `allowed` is the range the
  /// question was asked over, so records outside it are never sent.
  /// The records an `AIQueryScope` allows, mirroring the chat's ranges.
  static func meetings(in scope: AIQueryScope, from meetings: [Meeting]) -> [Meeting] {
    meetings.filter { scope.includes(recordID: $0.id, projectID: $0.spaceID) }
  }

  /// Which records a scope reaches. Kept apart from the search so the scope can
  /// be checked without building a model.
  static func meetings(in scope: AIChatScope, from meetings: [Meeting]) -> [Meeting] {
    switch scope {
    case .all, .files:
      meetings
    case .projects:
      meetings.filter { $0.spaceID != nil }
    }
  }

  /// The tasks whose record is within the allowed set.
  static func tasks(in allowedMeetings: [Meeting], from tasks: [MemoraTask]) -> [MemoraTask] {
    let allowedIDs = Set(allowedMeetings.map(\.id))
    return tasks.filter { task in
      guard let meetingID = task.meetingID else { return false }
      return allowedIDs.contains(meetingID)
    }
  }

  /// The tasks a scope reaches: a project scope never sees tasks from records
  /// that are not in a project.
  static func openTasks(in scope: AIChatScope, from tasks: [MemoraTask], meetings: [Meeting]) -> [MemoraTask] {
    let open = tasks.filter { !$0.isCompleted }
    switch scope {
    case .all:
      return open
    case .files:
      return open.filter { task in
        guard let meetingID = task.meetingID else { return false }
        return meetings.contains { $0.id == meetingID }
      }
    case .projects:
      let projectMeetingIDs = Set(Self.meetings(in: .projects, from: meetings).map(\.id))
      return open.filter { task in
        guard let meetingID = task.meetingID else { return false }
        return projectMeetingIDs.contains(meetingID)
      }
    }
  }

  /// Terms that carry no meaning on their own, so matching on them would rank
  /// records at random.
  private static let questionStopWords: Set<String> = [
    "こと", "です", "ます", "した", "する", "ある", "いる", "について", "なに", "どう",
    "何", "誰", "どこ", "いつ", "これ", "それ", "あれ", "から", "まで", "より", "ので",
    "けど", "って", "には", "では", "とは", "たい", "ない"
  ]

  /// The terms worth matching a question on. Punctuation is dropped, and a run
  /// of Japanese is cut into two-character pieces, so 「会議の決定は？」 can still
  /// reach records that talk about 会議 and 決定. A two-character run of kana
  /// alone is a grammatical particle, not a term, so it is left out.
  /// The Japanese letters a question can be made of. Built from scalar ranges,
  /// not a literal string, so the whole blocks are covered.
  private static let japaneseLetters: CharacterSet = {
    var set = CharacterSet()
    for value in 0x3041...0x309F { set.insert(Unicode.Scalar(value)!) } // hiragana
    for value in 0x30A0...0x30FF { set.insert(Unicode.Scalar(value)!) } // katakana
    for value in 0x4E00...0x9FFF { set.insert(Unicode.Scalar(value)!) } // CJK
    set.insert(Unicode.Scalar(0x3005)!) // 々
    return set
  }()

  static func questionWords(in question: String) -> [String] {
    let letters = CharacterSet.alphanumerics.union(japaneseLetters)

    var terms: Set<String> = []
    for token in question.components(separatedBy: letters.inverted) where !token.isEmpty {
      if token.allSatisfy(\.isASCII) {
        if token.count >= 2 {
          terms.insert(token)
        }
        continue
      }
      guard token.count >= 2 else { continue }
      if isWorthKeeping(token) {
        terms.insert(token)
      }
      let characters = Array(token)
      for index in 0..<(characters.count - 1) {
        let piece = String(characters[index...index + 1])
        if isWorthKeeping(piece) {
          terms.insert(piece)
        }
      }
    }
    return Array(terms)
  }

  /// A term is worth keeping unless it is a stop word or a two-character run of
  /// kana, which is almost always a particle.
  private static func isWorthKeeping(_ term: String) -> Bool {
    guard !questionStopWords.contains(term) else { return false }
    if term.count == 2, term.allSatisfy(isHiragana) {
      return false
    }
    return true
  }

  private static func isHiragana(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    return (0x3041...0x309F).contains(scalar.value)
  }

  func saveAIExchange(
    question: String,
    answer: String,
    scopeLabel: String,
    engineLabel: String,
    modelLabel: String?,
    cloudProvenance: AIConversationProvenance? = nil,
    webResearchReportID: UUID? = nil
  ) {
    aiHistory.insert(
      AIConversationEntry(
        id: UUID(),
        question: question,
        answer: answer,
        scopeLabel: scopeLabel,
        engineLabel: engineLabel,
        modelLabel: modelLabel,
        createdAt: .now,
        cloudProvenance: cloudProvenance,
        webResearchReportID: webResearchReportID
      ),
      at: 0
    )
    persistAIHistory()
  }

  func deleteAIHistoryEntry(_ id: UUID) {
    aiHistory.removeAll { $0.id == id }
    persistAIHistory()
  }
}

/// A bundle of transcript lines kept together when a record is too large to send
/// whole, with where it starts and how well it matches the question.
private struct ScoredSpan {
  static let maxLength = 800
  var start: TimeInterval
  var text: String
  var score: Int
}
