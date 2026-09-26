import Foundation

/// A record an AI answer was built from, so the answer can show its grounds.
/// The excerpts are read from the stored transcript, never from the model's own
/// wording, so an answer cannot cite a quote that is not in the record.
struct AIChatSource: Identifiable, Hashable {
  /// One stored line sent as grounds, with where it starts so it can be played.
  struct Excerpt: Hashable {
    var text: String
    var start: TimeInterval
  }

  var meetingID: UUID
  var title: String
  /// Up to three stored lines that matched the question, in time order.
  var excerpts: [Excerpt] = []

  var id: UUID { meetingID }
}
