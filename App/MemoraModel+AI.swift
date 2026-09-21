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

  /// Asks the chat a question. Returns false while an answer is already on its
  /// way, so the caller keeps the text instead of losing it to a refused send.
  @discardableResult
  func sendAIChat(_ question: String, attachment: AIAttachment? = nil) -> Bool {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || attachment != nil, !isAIChatResponding else { return false }

    let scope = aiScope
    let engine = aiEngine
    let provider = aiProvider
    let words = Self.questionWords(in: trimmed)
    let sources = aiSources(for: trimmed, scope: scope)
    let evidences = sources.map { meeting in
      (meeting: meeting, excerpt: Self.bestExcerpt(in: meeting, words: words))
    }
    var context = aiContext(for: sources, scope: scope)
    for evidence in evidences {
      guard let excerpt = evidence.excerpt else { continue }
      let stamp = MemoraFormat.duration(excerpt.start)
      context += "\n根拠の発言（\(evidence.meeting.displayTitle) \(stamp)）: \(excerpt.text)"
    }
    let history = aiConversationContext()
    let requestID = UUID()
    aiChatRequestID = requestID

    aiMessages.append(AIChatMessage(role: .user, text: trimmed))
    let placeholder = AIChatMessage(role: .assistant, text: "", isThinking: true)
    aiMessages.append(placeholder)
    isAIChatResponding = true

    // What the engines can read. Anything they cannot is named as not analysed
    // rather than sent as though it had been.
    var attachmentText = ""
    var unsupportedNote: String?
    if let attachment {
      switch AIAttachmentText.read(attachment) {
      case .text(let text):
        attachmentText = "添付「\(attachment.name)」:\n\(text)"
      case .unsupported(let reason):
        unsupportedNote = "添付「\(attachment.name)」はAI解析に対応していないため、内容は送信していません。\(reason)"
      }
    }

    aiChatTask?.cancel()
    aiChatTask = Task { [weak self] in
      guard let self else { return }
      // Tell the person what was left out before answering, so a send that
      // carried nothing never looks successful.
      if let unsupportedNote, let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
        self.aiMessages.insert(
          AIChatMessage(role: .assistant, text: unsupportedNote),
          at: index
        )
      }

      let promptContext = attachmentText.isEmpty ? context : "\(context)\n\n\(attachmentText)"
      let result = await AIEngineService.answer(
        engine: engine,
        provider: provider,
        question: trimmed,
        scopeLabel: scope.scopeLabel,
        context: promptContext,
        history: history
      )

      // A newer chat or question owns the screen now; this result is stale.
      guard !Task.isCancelled, self.aiChatRequestID == requestID else { return }

      let details = AIAnswerDetails(
        scopeLabel: scope.scopeLabel,
        engineLabel: AIEngineService.effectiveEngine(engine).label,
        modelLabel: AIEngineService.modelLabel(engine: engine, provider: provider),
        sourceCount: sources.count,
        generatedAt: .now
      )

      switch result {
      case .answer(let text):
        if let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
          self.aiMessages[index].text = text
          self.aiMessages[index].details = details
          self.aiMessages[index].isThinking = false
          // Only records that were actually sent are offered as grounds.
          self.aiMessages[index].sources = evidences.map { evidence in
            AIChatSource(
              meetingID: evidence.meeting.id,
              title: evidence.meeting.displayTitle,
              excerpt: evidence.excerpt?.text,
              start: evidence.excerpt?.start
            )
          }
        }
        self.saveAIExchange(
          question: trimmed,
          answer: text,
          scopeLabel: scope.scopeLabel,
          engineLabel: details.engineLabel,
          modelLabel: details.modelLabel
        )

      case .failure(let failure):
        // Cancellation is not a failure to report; the newer request answers.
        guard failure != .cancelled else { return }
        if let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
          self.aiMessages[index].text = failure.message
          self.aiMessages[index].details = details
          self.aiMessages[index].isThinking = false
        }
      }

      self.isAIChatResponding = false
      self.aiChatTask = nil
      self.aiChatRequestID = nil
    }

    return true
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
  /// to go on falls back to the most recent records.
  func aiSources(for question: String, scope: AIChatScope) -> [Meeting] {
    let scoped = Self.meetings(in: scope, from: meetings)
    let words = Self.questionWords(in: question)
    if !words.isEmpty {
      let matched = scoped
        .compactMap { meeting -> (meeting: Meeting, score: Int)? in
          let text = searchText(for: meeting)
          let score = words.filter { text.localizedCaseInsensitiveContains($0) }.count
          return score > 0 ? (meeting, score) : nil
        }
        .sorted { ($0.score, $0.meeting.createdAt) > ($1.score, $1.meeting.createdAt) }
        .prefix(5)
        .map(\.meeting)
      if !matched.isEmpty {
        return Array(matched)
      }
    }
    return Array(scoped.sorted { $0.createdAt > $1.createdAt }.prefix(3))
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

  /// A compact digest of the records an answer is built from, plus the open
  /// tasks, so a model answers from the data rather than from general knowledge.
  func aiContext(for sources: [Meeting], scope: AIChatScope) -> String {
    var lines: [String] = []

    let openTasks = Self.openTasks(in: scope, from: tasks, meetings: meetings)
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
