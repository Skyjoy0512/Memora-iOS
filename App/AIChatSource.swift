import Foundation

/// A record an AI answer was built from, so the answer can show its grounds.
/// The excerpt is read from the stored transcript, never from the model's own
/// wording, so an answer cannot cite a quote that is not in the record.
struct AIChatSource: Identifiable, Hashable {
  var meetingID: UUID
  var title: String
  /// The stored line that matched the question, when one did.
  var excerpt: String?
  /// Where that line starts in the recording, for seeking.
  var start: TimeInterval?

  var id: UUID { meetingID }
}
