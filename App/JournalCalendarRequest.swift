import Foundation

struct JournalCalendarRequest: Hashable {
  var date: Date
  var calendarIDs: [String]
  var enabled: Bool
  var refresh: Int

  var contentKey: Self {
    var key = self
    key.refresh = 0
    return key
  }
}
