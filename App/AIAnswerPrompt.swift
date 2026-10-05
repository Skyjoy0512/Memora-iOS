import Foundation

/// The prompt both engines send, so the two ask for the same thing.
enum AIAnswerPrompt {
  /// How an answer is laid out, so a long reply is not one wall of text. Kept
  /// apart from `ReadabilityGuide`, which governs summaries: those rules read
  /// oddly in a conversation, but a readable shape helps every answer.
  static let formatting = """
  回答は読みやすく整えます。話題が変わるところで改行し、長い一段落にせず短い段落に分けます。箇条書きが合うところは「- 」で並べ、特に大事な語や結論だけを **太字** にします。
  """

  static func text(question: String, scopeLabel: String, context: String, history: String) -> String {
    """
    対象: \(scopeLabel)

    \(history.isEmpty ? "" : "これまでのやりとり:\n\(history)\n")
    \(context.isEmpty ? "" : "記録:\n\(context)\n")
    質問: \(question)
    記録に基づいて、会話の相手に話すように自然に答えてください。記録に無いことは推測せず、無いと伝えてください。
    \(formatting)
    """
  }
}
