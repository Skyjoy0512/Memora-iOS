import Foundation

// Ask AI: the chat transcript and the answers shaped by the chosen scope.
extension MemoraModel {

  func startNewAIChat() {
    aiMessages = []
    isAIChatResponding = false
  }

  /// Appends a turn to the Ask AI chat and answers it a moment later.
  func sendAIChat(_ question: String) {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isAIChatResponding else { return }

    let scope = aiScope
    aiMessages.append(AIChatMessage(role: .user, text: trimmed))
    let placeholder = AIChatMessage(role: .assistant, text: "", isThinking: true)
    aiMessages.append(placeholder)
    isAIChatResponding = true

    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(1_100))
      guard let self else { return }
      let canned = self.aiAnswer(for: trimmed, scope: scope)
      // Only the records the question actually reaches are used, so the answer
      // is built on what it can also point back to.
      let sources = self.aiSources(for: trimmed, scope: scope)
      let engineAnswer = await AIEngineService.answer(
        question: trimmed,
        scopeLabel: scope.scopeLabel,
        context: self.aiContext(for: sources)
      )
      let answer = engineAnswer ?? canned.answer
      let thinking = engineAnswer == nil
        ? canned.thinking
        : "\(scope.scopeLabel)の記録\(sources.count)件をもとに、選んだAIエンジンで生成しました。"
      if let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
        self.aiMessages[index].text = answer
        self.aiMessages[index].thinking = thinking
        self.aiMessages[index].isThinking = false
        // A fallback has no grounds, so it cites nothing.
        if engineAnswer != nil {
          self.aiMessages[index].sources = sources.map {
            AIChatSource(meetingID: $0.id, title: $0.displayTitle)
          }
        }
      }
      self.isAIChatResponding = false
      self.saveAIExchange(question: trimmed, answer: answer, scopeLabel: scope.scopeLabel)
    }
  }

  /// The records a question reaches: those whose own text contains its words,
  /// ranked by how many of them match, then by recency. A question with nothing
  /// to go on falls back to the most recent records.
  func aiSources(for question: String, scope: AIChatScope) -> [Meeting] {
    let scoped: [Meeting]
    switch scope {
    case .all, .files:
      scoped = meetings
    case .projects:
      scoped = meetings.filter { $0.spaceID != nil }
    }

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
  func aiContext(for sources: [Meeting]) -> String {
    var lines: [String] = []

    let openTasks = tasks.filter { !$0.isCompleted }
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

  /// The fallback shown only when no engine can answer. It says so instead of
  /// inventing decisions, tasks, or quotes.
  func aiAnswer(for question: String, scope: AIChatScope = .all) -> (answer: String, thinking: String) {
    (
      "この端末ではAIエンジンを利用できないため、記録に基づく回答を作成できませんでした。設定の「AI整理」でエンジンとキーを確認してください。",
      ""
    )
  }

  func saveAIExchange(question: String, answer: String, scopeLabel: String) {
    aiHistory.insert(
      AIConversationEntry(
        id: UUID(),
        question: question,
        answer: answer,
        scopeLabel: scopeLabel,
        createdAt: .now
      ),
      at: 0
    )
    persistAIHistory()
  }
}
