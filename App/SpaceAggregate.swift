import Foundation

/// What a project tile shows: how many records it holds and the newest ones'
/// icons. Counted once when the records change rather than rescanned per tile.
struct SpaceAggregate {
  var meetingCount: Int = 0
  var icons: [String] = []
  var latestDate: Date?
}
