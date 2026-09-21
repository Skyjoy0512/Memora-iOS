import Foundation

/// The content one request would send, kept apart from the network call so what
/// goes out can be checked without sending anything.
struct AIRequestContent {
  var question: String
  var scopeLabel: String
  /// What the model is given: the allowed records, the tasks that belong to
  /// them, and any attachment text.
  var context: String
  /// The records actually included, each with a stored line when one matched.
  var sources: [AIChatSource]
  /// Said instead of sending an attachment the engines cannot read.
  var unsupportedAttachmentNote: String?
}
