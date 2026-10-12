import Foundation

/// One row of the journal's day timeline. The id is namespaced by kind so a
/// record, an event and the "now" line can never share one.
enum JournalTimelineItem: Identifiable {
  case entry(LifeLogEntry)
  case record(Meeting)
  case calendarEvent(JournalCalendarEvent)
  case movement(JournalMovement)
  case nowMarker
  case completedTask(MemoraTask)

  var id: String {
    switch self {
    case .entry(let entry): "entry-\(entry.id.uuidString)"
    case .record(let meeting): "record-\(meeting.id.uuidString)"
    case .calendarEvent(let event): "event-\(event.id)"
    case .movement(let movement): "movement-\(movement.id)"
    case .nowMarker: "nowMarker"
    case .completedTask(let task): "completedTask-\(task.id.uuidString)"
    }
  }

  func date(on day: Date, now: Date = .now) -> Date {
    switch self {
    case .entry(let entry): entry.occurredAt
    case .record(let meeting): meeting.createdAt
    case .calendarEvent(let event): max(event.start, Calendar.current.startOfDay(for: day))
    case .movement(let movement): movement.start
    case .nowMarker: now
    case .completedTask(let task): task.completedAt ?? day
    }
  }
}
