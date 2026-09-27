import EventKit
import Foundation
import SwiftUI

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

  /// The events that overlap one day, for the journal. Read on every display, so
  /// the calendar stays the source of truth and nothing is stored twice. Reading
  /// is done off the main actor, since EventKit can be slow.
  static func events(on day: Date, calendarIdentifiers: [String]? = nil) async -> [JournalCalendarEvent] {
    guard access == .granted else { return [] }
    return await Task.detached(priority: .userInitiated) { () -> [JournalCalendarEvent] in
      readEvents(on: day, calendarIdentifiers: calendarIdentifiers)
    }.value
  }

  private static func readEvents(on day: Date, calendarIdentifiers: [String]?) -> [JournalCalendarEvent] {
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: day)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

    let store = EKEventStore()
    let calendars: [EKCalendar]? = calendarIdentifiers.map { ids in
      store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
    }
    // Start the lookup a day early so an event that began before midnight but
    // reaches into this day is found.
    let lookupStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
    let lookupEnd = calendar.date(byAdding: .day, value: 1, to: dayEnd) ?? dayEnd
    let predicate = store.predicateForEvents(withStart: lookupStart, end: lookupEnd, calendars: calendars)

    return store.events(matching: predicate)
      .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
      .sorted { $0.startDate < $1.startDate }
      .compactMap { event in
        guard let identifier = event.eventIdentifier else { return nil }
        return JournalCalendarEvent(
          eventIdentifier: identifier,
          start: event.startDate,
          end: event.endDate,
          title: event.title ?? "予定",
          isAllDay: event.isAllDay,
          calendarTitle: event.calendar.title,
          calendarColor: event.calendar.cgColor.flatMap { Color(cgColor: $0) },
          location: event.location
        )
      }
  }
}
