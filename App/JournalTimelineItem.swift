import Foundation

/// One row of the journal's day timeline. The id is namespaced by kind so a
/// record, an event and the "now" line can never share one.
enum JournalTimelineItem: Identifiable {
  case entry(LifeLogEntry)
  case calendarEvent(JournalCalendarEvent)
  case movement(JournalMovement)
  case nowMarker

  var id: String {
    switch self {
    case .entry(let entry): "entry-\(entry.id.uuidString)"
    case .calendarEvent(let event): "event-\(event.id)"
    case .movement(let movement): "movement-\(movement.id)"
    case .nowMarker: "nowMarker"
    }
  }
}
