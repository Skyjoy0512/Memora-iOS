import Foundation

/// A record an AI answer was built from, so the answer can show its grounds.
struct AIChatSource: Identifiable, Hashable {
  var meetingID: UUID
  var title: String

  var id: UUID { meetingID }
}
