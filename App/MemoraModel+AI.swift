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

  /// A canned answer with its reasoning, shaped by the question and scope.
  func aiAnswer(for question: String, scope: AIChatScope = .all) -> (answer: String, thinking: String) {
    let lead = scope == .all ? "" : "対象を\(scope.scopeLabel)に絞って確認しました。"

    if question.contains("タスク") {
      return (
        "未完了のタスクは「初回録音フローの仕様を確定する」と「Acme社へセキュリティ資料を送る」の2件です。どちらも元の会議にひも付いていて、そこから発言まで戻れます。",
        lead + "タスクを会議横断で集め、期限の近い順に並べました。"
      )
    }
    if question.contains("決") {
      return (
        "直近では、録音とタスク抽出を最優先で提供すること、会議データは既定で端末内に保存することが決まっています。クラウド同期の提供時期はまだ未決です。",
        lead + "決定事項を新しい会議から順に読み、未決事項と分けて確認しました。"
      )
    }
    return (
      lead + "次に行うことは、初回録音フローの仕様確定と、Acme社へセキュリティ資料を送ることです。録音開始の速さを優先し、データは既定で端末内に保存する方針が確認されています。",
      lead + "まず未完了の行動を集め、次に関連する会議から根拠をたどりました。"
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
