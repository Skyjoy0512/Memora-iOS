import EventKit
import Foundation

/// A fresh, device-only EventKit context. It is never encoded into app records,
/// AI history, or approvals, and never requests or widens calendar access.
@MainActor
final class CalendarEventEditContext {
  let store: EKEventStore
  let event: EKEvent

  init?(snapshot: JournalCalendarEvent) {
    guard CalendarService.access == .granted, !snapshot.eventIdentifier.isEmpty,
          let calendarID = snapshot.calendarIdentifier, !calendarID.isEmpty,
          snapshot.start.timeIntervalSince1970.isFinite, snapshot.end.timeIntervalSince1970.isFinite,
          snapshot.end >= snapshot.start else { return nil }
    let store = EKEventStore()
    guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else { return nil }
    // A bounded window plus the occurrence start avoids selecting another
    // instance when EventKit gives a recurring series a shared identifier.
    let predicate = store.predicateForEvents(withStart: snapshot.start.addingTimeInterval(-1),
      end: snapshot.start.addingTimeInterval(1), calendars: [calendar])
    guard let event = store.events(matching: predicate).first(where: { candidate in
      guard let id = candidate.eventIdentifier, let start = candidate.startDate, let end = candidate.endDate,
            candidate.calendar?.calendarIdentifier == calendarID else { return false }
      return CalendarEventEditPolicy.matchesOccurrence(id: id, start: start, end: end,
        expectedID: snapshot.eventIdentifier, expectedStart: snapshot.start, expectedEnd: snapshot.end)
    }), CalendarService.allowsEditing(event) else { return nil }
    self.store = store
    self.event = event
  }

  var isEditable: Bool { CalendarService.allowsEditing(event) }
}
