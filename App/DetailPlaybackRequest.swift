import Foundation

/// A request to bring the open meeting detail to its transcript at a time. Used
/// when an AI answer's source line points at the record already on screen, so no
/// second copy is stacked and the existing player does the seeking.
struct DetailPlaybackRequest: Equatable {
  var id = UUID()
  var meetingID: UUID
  /// Where to play from. `nil` only moves to the transcript without playing,
  /// such as when a source's title is tapped.
  var time: TimeInterval?
}
