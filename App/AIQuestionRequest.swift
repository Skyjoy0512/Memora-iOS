import Foundation

/// One question with everything the answer depends on, captured when it is sent.
/// The screen can change while the answer is being written; what was asked, and
/// the range it was asked over, cannot.
struct AIQuestionRequest: Identifiable, Equatable {
  var id = UUID()
  var question: String
  var scope: AIQueryScope
  var attachment: AIAttachment?

  /// The question as it is sent: an attachment on its own still needs asking.
  var effectiveQuestion: String {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty else { return trimmed }
    return "「\(attachment?.name ?? "添付ファイル")」を確認して"
  }
}
