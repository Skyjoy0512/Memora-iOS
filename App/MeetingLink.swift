import Foundation

/// A link to a meeting that opens it in the app. Shared alongside the summary
/// so a recipient with Memora can jump straight to it.
enum MeetingLink {
  static func url(for meetingID: UUID) -> URL? {
    URL(string: "memora://meeting/\(meetingID.uuidString)")
  }
}
