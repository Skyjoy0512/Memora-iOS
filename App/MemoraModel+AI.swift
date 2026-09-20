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
      let engineAnswer = await AIEngineService.answer(
        question: trimmed,
        scopeLabel: scope.scopeLabel,
        context: self.aiContext()
      )
      let answer = engineAnswer ?? canned.answer
      let thinking = engineAnswer == nil
        ? canned.thinking
        : "\(scope.scopeLabel)の記録から、選んだAIエンジンで生成しました。"
      if let index = self.aiMessages.firstIndex(where: { $0.id == placeholder.id }) {
        self.aiMessages[index].text = answer
        self.aiMessages[index].thinking = thinking
        self.aiMessages[index].isThinking = false
      }
      self.isAIChatResponding = false
      self.saveAIExchange(question: trimmed, answer: answer, scopeLabel: scope.scopeLabel)
    }
  }

  /// A compact digest of the data, so an on-device model answers from the
  /// records rather than from general knowledge.
  func aiContext() -> String {
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

    let recent = meetings.sorted { $0.createdAt > $1.createdAt }.prefix(3)
    if !recent.isEmpty {
      lines.append("最近の会議:")
      lines.append(contentsOf: recent.map { meeting in
        meeting.summary.isEmpty ? "- \(meeting.title)" : "- \(meeting.title): \(meeting.summary)"
      })
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
  }
}
