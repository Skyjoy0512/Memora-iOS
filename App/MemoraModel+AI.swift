import Foundation

// Ask AI: the chat transcript and the answers shaped by the chosen scope.
extension MemoraModel {

  /// Starts a fresh chat. Whatever was being answered is cancelled, so its
  /// result can never land in the new conversation.
  func startNewAIChat() {
    aiChatTask?.cancel()
    aiChatTask = nil
    aiChatRequestID = nil
    aiMessages = []
    isAIChatResponding = false
  }

  /// Changes what new questions look across, starting a fresh chat so an answer
  /// produced for the old range cannot sit beside a question asked of the new
  /// one. Saved history is left alone.
  func changeAIScope(_ scope: AIChatScope) {
    guard scope != aiScope else { return }
    aiScope = scope
    startNewAIChat()
  }

  /// Asks the chat a question. Returns false while an answer is already on its
  /// way, so the caller keeps the text instead of losing it to a refused send.
  @discardableResult
  func sendAIChat(_ question: String, attachment: AIAttachment? = nil) -> Bool {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || attachment != nil, !isAIChatResponding else { return false }

    let engine = aiEngine
    let provider = aiProvider
    let scope = aiScope
    let history = aiConversationContext()
    let requestID = UUID()
    aiChatRequestID = requestID

    aiMessages.append(AIChatMessage(role: .user, text: trimmed))
    let placeholder = AIChatMessage(role: .assistant, text: "", isThinking: true)
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
        engine: engine,
        provider: provider
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

      switch outcome.result {
      case .answer(let text):
        if let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
          self.aiMessages[index].text = text
          self.aiMessages[index].details = outcome.details
          self.aiMessages[index].isThinking = false
          // Only records that were actually sent are offered as grounds.
          self.aiMessages[index].sources = outcome.sources
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
    engine: AIEngine,
    provider: CloudProvider
  ) async -> AIAnswerOutcome {
    let content = Self.requestContent(
      for: request,
      scopeLabel: scopeLabel,
      allowedMeetings: allowedMeetings,
      tasks: scopedTasks
    )

    // A question that is only an attachment no engine can read has nothing to
    // answer. Saying so is better than answering from unrelated recent records.
    if request.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       request.attachment != nil,
       content.unsupportedAttachmentNote != nil {
      let details = AIAnswerDetails(
        scopeLabel: scopeLabel,
        engineLabel: AIEngineService.effectiveEngine(engine).label,
        modelLabel: AIEngineService.modelLabel(engine: engine, provider: provider),
        sourceCount: 0,
        generatedAt: .now
      )
      return AIAnswerOutcome(
        question: content.question,
        scopeLabel: scopeLabel,
        result: .failure(.attachmentNotAnalysed),
        sources: [],
        details: details,
        unsupportedAttachmentNote: content.unsupportedAttachmentNote
      )
    }

    let result = await AIEngineService.answer(
      engine: engine,
      provider: provider,
      question: content.question,
      scopeLabel: scopeLabel,
      context: content.context,
      history: history
    )

    let details = AIAnswerDetails(
      scopeLabel: scopeLabel,
      engineLabel: AIEngineService.effectiveEngine(engine).label,
      modelLabel: AIEngineService.modelLabel(engine: engine, provider: provider),
      sourceCount: content.sources.count,
      generatedAt: .now
    )

    return AIAnswerOutcome(
      question: content.question,
      scopeLabel: scopeLabel,
      result: result,
      // Only an answer is given grounds; a failure has none to show.
      sources: result.text == nil ? [] : content.sources,
      details: details,
      unsupportedAttachmentNote: content.unsupportedAttachmentNote
    )
  }

  /// Assembles what a request would send. Pure, so a test can check that records
  /// outside the requested range are absent without calling an engine.
  static func requestContent(
    for request: AIQuestionRequest,
    scopeLabel: String,
    allowedMeetings: [Meeting],
    tasks: [MemoraTask]
  ) -> AIRequestContent {
    let question = request.effectiveQuestion
    let words = questionWords(in: question)
    let ranked = rank(meetings: allowedMeetings, words: words)
    let evidences = ranked.map { meeting in
      (meeting: meeting, excerpt: bestExcerpt(in: meeting, words: words))
    }

    var context = context(for: ranked, tasks: tasks)
    for evidence in evidences {
      guard let excerpt = evidence.excerpt else { continue }
      let stamp = MemoraFormat.duration(excerpt.start)
      context += "\n参考資料の発言（\(evidence.meeting.displayTitle) \(stamp)）: \(excerpt.text)"
    }

    // What the engines can read. Anything they cannot is named as not analysed
    // rather than sent as though it had been.
    var attachmentText = ""
    var unsupportedNote: String?
    if let attachment = request.attachment {
      switch AIAttachmentText.read(attachment) {
      case .text(let text):
        attachmentText = "添付「\(attachment.name)」:\n\(text)"
      case .unsupported(let reason):
        unsupportedNote = "添付「\(attachment.name)」はAI解析に対応していないため、内容は送信していません。\(reason)"
      }
    }
    if !attachmentText.isEmpty {
      context += "\n\n\(attachmentText)"
    }

    return AIRequestContent(
      question: question,
      scopeLabel: scopeLabel,
      context: context,
      sources: evidences.map { evidence in
        AIChatSource(
          meetingID: evidence.meeting.id,
          title: evidence.meeting.displayTitle,
          excerpt: evidence.excerpt?.text,
          start: evidence.excerpt?.start
        )
      },
      unsupportedAttachmentNote: unsupportedNote
    )
  }

  /// The records worth sending, ranked by how many of the question's terms they
  /// contain and then by recency. Falls back to the most recent ones.
  static func rank(meetings: [Meeting], words: [String]) -> [Meeting] {
    guard !words.isEmpty else {
      return Array(meetings.sorted { $0.createdAt > $1.createdAt }.prefix(3))
    }
    let matched = meetings
      .compactMap { meeting -> (meeting: Meeting, score: Int)? in
        let text = searchableText(of: meeting)
        let score = words.filter { text.localizedCaseInsensitiveContains($0) }.count
        return score > 0 ? (meeting, score) : nil
      }
      .sorted { ($0.score, $0.meeting.createdAt) > ($1.score, $1.meeting.createdAt) }
      .prefix(5)
      .map(\.meeting)
    return matched.isEmpty
      ? Array(meetings.sorted { $0.createdAt > $1.createdAt }.prefix(3))
      : Array(matched)
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

  /// The digest of the records and the tasks that belong to them.
  static func context(for sources: [Meeting], tasks allowedTasks: [MemoraTask]) -> String {
    var lines: [String] = []

    let openTasks = allowedTasks.filter { !$0.isCompleted }
    if !openTasks.isEmpty {
      lines.append("未完了のタスク:")
      lines.append(contentsOf: openTasks.map { task in
        if let assignee = task.assignee, !assignee.isEmpty {
          return "- \(task.title)（\(assignee)）"
        }
        return "- \(task.title)"
      })
    }

    if !sources.isEmpty {
      lines.append("会議の記録:")
      for meeting in sources {
        lines.append("\(meeting.displayTitle)（\(meeting.createdAt.formatted(date: .numeric, time: .omitted))）")
        if !meeting.summary.isEmpty {
          lines.append("要約: \(meeting.summary)")
        }
        for decision in meeting.decisions.prefix(3) {
          lines.append("決定: \(decision)")
        }
        for question in meeting.openQuestions.prefix(3) {
          lines.append("未決: \(question)")
        }
        if meeting.summary.isEmpty, let excerpt = meeting.transcript.first {
          lines.append("発言: \(excerpt.text.prefix(400))")
        }
      }
    }

    return lines.joined(separator: "\n")
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

  /// The stored line that best matches the question. Read from the record, so
  /// the quote shown with an answer is always one that is really there.
  static func bestExcerpt(
    in meeting: Meeting,
    words: [String]
  ) -> (text: String, start: TimeInterval)? {
    guard !words.isEmpty else { return nil }
    return meeting.transcript
      .map { segment -> (segment: TranscriptSegment, score: Int) in
        (segment, words.filter { segment.text.localizedCaseInsensitiveContains($0) }.count)
      }
      .filter { $0.score > 0 }
      .max { $0.score < $1.score }
      .map { ($0.segment.text, $0.segment.timestamp) }
  }

  /// The records a question reaches: those whose own text contains its words,
  /// ranked by how many of them match, then by recency. A question with nothing
  /// to go on falls back to the most recent records. `allowed` is the range the
  /// question was asked over, so records outside it are never sent.
  /// The records an `AIQueryScope` allows, mirroring the chat's ranges.
  static func meetings(in scope: AIQueryScope, from meetings: [Meeting]) -> [Meeting] {
    switch scope {
    case .file(let id):
      meetings.filter { $0.id == id }
    case .space(let id):
      meetings.filter { $0.spaceID == id }
    case .global:
      meetings
    }
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

  /// The terms worth matching a question on. Punctuation is dropped, and a run
  /// of Japanese is cut into two-character pieces, so 「会議の決定は？」 can still
  /// reach records that talk about 会議 and 決定.
  static func questionWords(in question: String) -> [String] {
    let letters = CharacterSet.alphanumerics
      .union(CharacterSet(charactersIn: "ぁ-んァ-ヶ一-龠々ー"))

    var terms: Set<String> = []
    for token in question.components(separatedBy: letters.inverted) where !token.isEmpty {
      if token.allSatisfy(\.isASCII) {
        if token.count >= 2 {
          terms.insert(token)
        }
        continue
      }
      guard token.count >= 2 else { continue }
      terms.insert(token)
      let characters = Array(token)
      for index in 0..<(characters.count - 1) {
        terms.insert(String(characters[index...index + 1]))
      }
    }
    return Array(terms)
  }

  func saveAIExchange(
    question: String,
    answer: String,
    scopeLabel: String,
    engineLabel: String,
    modelLabel: String?
  ) {
    aiHistory.insert(
      AIConversationEntry(
        id: UUID(),
        question: question,
        answer: answer,
        scopeLabel: scopeLabel,
        engineLabel: engineLabel,
        modelLabel: modelLabel,
        createdAt: .now
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
