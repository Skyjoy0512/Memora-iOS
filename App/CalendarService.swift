import EventKit
import Foundation

struct UpcomingMeeting: Identifiable, Hashable {
  var id: String
  var title: String
  var start: Date
  var end: Date
}

enum CalendarAccess {
  case unknown
  case denied
  case granted
}

/// Reads the next events from the calendar so Home can offer to record them.
enum CalendarService {
  static var access: CalendarAccess {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess, .authorized:
      return .granted
    case .denied, .restricted, .writeOnly:
      return .denied
    default:
      return .unknown
    }
  }

  static func requestAccess() async -> Bool {
    do {
      return try await EKEventStore().requestFullAccessToEvents()
    } catch {
      return false
    }
  }

  static func upcoming(limit: Int = 3, withinDays days: Int = 7) async -> [UpcomingMeeting] {
    let store = EKEventStore()
    let now = Date()
    guard let end = Calendar.current.date(byAdding: .day, value: days, to: now) else { return [] }

    let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
    let events = store.events(matching: predicate)
      .filter { !$0.isAllDay }
      .sorted { $0.startDate < $1.startDate }

    return events.prefix(limit).map { event in
      UpcomingMeeting(
        id: event.eventIdentifier ?? UUID().uuidString,
        title: event.title ?? "会議",
        start: event.startDate,
        end: event.endDate
      )
    }
  }
}
