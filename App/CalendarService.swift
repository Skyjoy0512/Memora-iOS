import EventKit
import Foundation
import SwiftUI

/// Reads the next events from the calendar so Home can offer to record them.
enum CalendarService {
  @MainActor private static var aiObservationStore: EKEventStore?

  /// Keep a store alive so EventKit posts permission/database changes during an AI conversation.
  @MainActor static func beginAIObservation() {
    guard access == .granted, aiObservationStore == nil else { return }
    aiObservationStore = EKEventStore()
  }

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

  static func allowsEditing(_ event: EKEvent) -> Bool {
    CalendarEventEditPolicy.allowsEditing(hasFullAccess: access == .granted,
      calendarAllowsChanges: event.calendar?.allowsContentModifications == true,
      isCancelled: event.status == .canceled, isOwnedByCurrentUser: event.organizer?.isCurrentUser ?? true)
  }

  enum AddEventError: Error {
    case accessDenied
    case noCalendar
  }

  /// Adds an event to the default calendar, asking for access first when it
  /// has not been decided yet.
  static func addEvent(title: String, start: Date, end: Date, location: String?, notes: String?) async throws {
    if access != .granted {
      guard await requestAccess() else { throw AddEventError.accessDenied }
    }
    let store = EKEventStore()
    guard let calendar = store.defaultCalendarForNewEvents else { throw AddEventError.noCalendar }
    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = start
    event.endDate = end
    event.location = location
    event.notes = notes
    event.calendar = calendar
    try store.save(event, span: .thisEvent)
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
        end: event.endDate,
        isOnline: hasMeetingLink(event),
        calendarColor: event.calendar?.cgColor.map { Color(cgColor: $0) }
      )
    }
  }

  private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]

  private static func hasMeetingLink(_ event: EKEvent) -> Bool {
    let text = [event.url?.absoluteString, event.location, event.notes]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")
    return meetingHosts.contains { text.contains($0) }
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
        guard let identifier = event.eventIdentifier, let sourceCalendar = event.calendar else { return nil }
        return JournalCalendarEvent(
          eventIdentifier: identifier,
          start: event.startDate,
          end: event.endDate,
          title: event.title ?? "予定",
          isAllDay: event.isAllDay,
          calendarTitle: sourceCalendar.title,
          calendarColor: sourceCalendar.cgColor.flatMap { Color(cgColor: $0) },
          location: event.location,
          allowsEditing: allowsEditing(event),
          calendarIdentifier: sourceCalendar.calendarIdentifier
        )
      }
  }
}
