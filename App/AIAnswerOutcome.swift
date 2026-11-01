import Foundation

/// Everything one answered (or failed) question produced: the answer or the
/// reason there is none, the records it was allowed to use and actually used,
/// and the details of what ran. Both the chat and the focused question screen
/// work from this, so they cannot drift apart.
struct AIAnswerOutcome {
  var question: String
  var scopeLabel: String
  var result: AIAnswerResult
  /// The records sent with the question, each with a line from the stored
  /// transcript when one matched.
  var sources: [AIChatSource]
  var details: AIAnswerDetails
  /// Said when an attachment could not be read, so a send that carried nothing
  /// never looks like it was understood.
  var unsupportedAttachmentNote: String?
  /// Said when the attachment or the recent exchanges were trimmed to fit the
  /// engine's budget, so a short answer is not mistaken for a complete one.
  var contextNote: String?
  var sourceCitations: [ProjectCitation] = []
  var attachmentCitations: [AIAttachmentCitation] = []

  var isAnswer: Bool { result.text != nil }
}
