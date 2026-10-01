import Foundation

/// A record a teammate shared, on its own or inside a project. It is a
/// read-only snapshot: it is never merged into this person's own records.
struct SharedRecord: Identifiable, Hashable {
  var itemID: String
  var meeting: Meeting
  var tasks: [MemoraTask]
  var ownerName: String
  /// The project it came from, when the owner had filed it in one.
  var projectName: String?
  var updatedAt: Date

  var id: String { "\(itemID)/\(meeting.id.uuidString)" }
}
