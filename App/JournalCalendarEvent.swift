import SwiftUI

/// One calendar event as shown in the journal. Read from EventKit each time,
/// never stored, so the calendar stays the single source of truth.
struct JournalCalendarEvent: Identifiable, Hashable {
  /// The event's own identifier, used to match a recording to its event.
  var eventIdentifier: String
  var start: Date
  var end: Date
  var title: String
  var isAllDay: Bool
  var calendarTitle: String
  var calendarColor: Color?
  var location: String?
  /// Set when a recording is tied to this event, so one row can open it.
  var meetingID: UUID?
  /// A presentation hint only. The event is looked up and checked again on edit.
  var allowsEditing = false
  var calendarIdentifier: String?

  /// Identifier plus start, so each repeat of a recurring event is its own item.
  var id: String { "\(eventIdentifier)@\(start.timeIntervalSince1970)" }
}
