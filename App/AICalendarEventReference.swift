import Foundation

/// Only locally read fields can populate the agenda. The UUID is a per-conversation reference.
struct AICalendarEventReference: Hashable, Sendable, Identifiable {
  var id = UUID()
  var sourceID: String
  var title: String
  var start: Date
  var end: Date
  var isAllDay: Bool

  var isValid: Bool {
    !sourceID.isEmpty && sourceID.utf8.count <= 2_048 && !title.isEmpty && title.count <= 200
      && start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite && end >= start
  }
}
