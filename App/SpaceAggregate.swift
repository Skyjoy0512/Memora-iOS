import Foundation

/// What a project tile shows: how many records it holds and the newest ones'
/// icons. Counted once when the records change rather than rescanned per tile.
struct SpaceAggregate: Equatable {
  var meetingCount: Int = 0
  var icons: [MemoraIcon] = []
  var latestDate: Date?
}
