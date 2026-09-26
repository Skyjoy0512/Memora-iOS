import Foundation

/// Builds a day's timeline from journal records, calendar events and recordings.
/// Pure, so the ordering rules can be checked without a view.
enum JournalTimelineBuilder {
  struct Result {
    /// Time-of-day rows in ascending order, with the "now" marker among them.
    var items: [JournalTimelineItem]
    /// All-day events, kept apart so they can sit under the date heading.
    var allDayEvents: [JournalCalendarEvent]
  }

  /// Two station passes closer than this read as one journey.
  static let movementGap: TimeInterval = 60 * 60
  /// How far a recording's start may sit from an event's start to belong to it.
  static let eventMatchWindow: TimeInterval = 12 * 60 * 60

  static func build(
    day: Date,
    entries: [LifeLogEntry],
    events: [JournalCalendarEvent],
    meetings: [Meeting],
    now: Date = .now,
    calendar: Calendar = .current
  ) -> Result {
    let dayEntries = entries.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
    let timedEvents = events.filter { !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: day) }
    let allDayEvents = events.filter { $0.isAllDay && calendar.isDate($0.start, inSameDayAs: day) }

    // An event with a recording tied to it becomes one row that opens the
    // recording, and the recording's own journal line is dropped so the same
    // conversation is not listed twice.
    var matchedMeetingIDs: Set<UUID> = []
    var timedItems: [(date: Date, item: JournalTimelineItem)] = []
    for event in timedEvents {
      var resolved = event
      if let meeting = recording(for: event, in: meetings) {
        resolved.meetingID = meeting.id
        matchedMeetingIDs.insert(meeting.id)
      }
      timedItems.append((event.start, .calendarEvent(resolved)))
    }

    let remaining = dayEntries.filter { entry in
      guard let meetingID = entry.meetingID else { return true }
      return !matchedMeetingIDs.contains(meetingID)
    }
    let passes = remaining
      .filter { $0.origin == .stationPass }
      .sorted { $0.createdAt < $1.createdAt }
    let others = remaining.filter { $0.origin != .stationPass }

    var paired: [(date: Date, item: JournalTimelineItem)] =
      others.map { ($0.createdAt, .entry($0)) }
    paired.append(contentsOf: timedItems)
    paired.append(contentsOf: movements(from: passes).map { ($0.start, .movement($0)) })

    if calendar.isDate(day, inSameDayAs: now) {
      paired.append((now, .nowMarker))
    }

    let items = paired
      .enumerated()
      .sorted { lhs, rhs in
        lhs.element.date == rhs.element.date
          ? lhs.offset < rhs.offset
          : lhs.element.date < rhs.element.date
      }
      .map(\.element.item)

    return Result(
      items: items,
      allDayEvents: allDayEvents.sorted { $0.start < $1.start }
    )
  }

  /// The recording that belongs to an event: same event identifier and a start
  /// within the window, so a later repeat of a recurring event is not matched.
  static func recording(for event: JournalCalendarEvent, in meetings: [Meeting]) -> Meeting? {
    meetings.first { meeting in
      meeting.calendarEventID == event.eventIdentifier
        && abs(meeting.createdAt.timeIntervalSince(event.start)) <= eventMatchWindow
    }
  }

  /// Groups station passes into journeys, starting a new one after a long gap.
  static func movements(from passes: [LifeLogEntry]) -> [JournalMovement] {
    guard !passes.isEmpty else { return [] }
    var result: [JournalMovement] = []
    var current: [LifeLogEntry] = []
    for pass in passes {
      if let last = current.last, pass.createdAt.timeIntervalSince(last.createdAt) > movementGap {
        result.append(JournalMovement(entries: current))
        current = []
      }
      current.append(pass)
    }
    if !current.isEmpty {
      result.append(JournalMovement(entries: current))
    }
    return result
  }
}
