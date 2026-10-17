import Foundation

extension MemoraModel {
  /// Reads a finished answer aloud, or stops it when that answer is the one
  /// already playing.
  func toggleAnswerSpeech(_ message: AIChatMessage) {
    guard !message.text.isEmpty else { return }
    answerSpeech.toggle(messageID: message.id, text: Self.spokenAnswerText(message.text))
  }

  func isSpeakingAnswer(_ messageID: UUID) -> Bool {
    answerSpeech.speakingMessageID == messageID
  }

  func stopAnswerSpeech() {
    answerSpeech.stop()
  }

  /// The answer as a sentence to read: the structured-UI block, citation
  /// markers and Markdown symbols are removed, so nothing is read as
  /// punctuation and no invented words are added.
  static func spokenAnswerText(_ text: String) -> String {
    let markdown = AnswerCitations.stripped(NativeAIInterface.response(text).markdown)
    return markdown
      .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
      .replacingOccurrences(of: #"[`*_#>]"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
