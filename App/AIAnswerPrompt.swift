import Foundation

/// The prompt both engines send, so the two ask for the same thing.
enum AIAnswerPrompt {
  static func text(question: String, scopeLabel: String, context: String, history: String) -> String {
    """
    対象: \(scopeLabel)

    \(history.isEmpty ? "" : "これまでのやりとり:\n\(history)\n")
    \(context.isEmpty ? "" : "記録:\n\(context)\n")
    質問: \(question)
    記録に基づいて簡潔に答えてください。記録に無いことは推測せず、無いと伝えてください。
    """
  }
}
