import Foundation

enum JournalInsertionTime {
  static func suggestion(on day: Date, previous: Date? = nil, next: Date? = nil,
                         now: Date = .now, calendar: Calendar = .current) -> Date {
    let start = calendar.startOfDay(for: day)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    let last = end.addingTimeInterval(-1)
    func clamped(_ value: Date) -> Date { min(max(value, start), last) }
    let proposed: Date
    if let previous, let next {
      let lower = clamped(previous), upper = clamped(next)
      proposed = lower.addingTimeInterval(max(0, upper.timeIntervalSince(lower)) / 2)
    } else if let previous {
      let following = previous.addingTimeInterval(30 * 60)
      proposed = calendar.isDate(day, inSameDayAs: now) ? max(following, now) : following
    } else if let next {
      proposed = next.addingTimeInterval(-30 * 60)
    } else {
      proposed = calendar.isDate(day, inSameDayAs: now) ? now
        : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start
    }
    return clamped(proposed)
  }

  /// A clock marker has no event date. Skip it without changing the visible
  /// timeline or counting it as another event in the suggested interval.
  static func suggestion(on day: Date, after index: Int, dates: [Date?],
                         now: Date = .now, calendar: Calendar = .current) -> Date {
    let split = index < 0 ? 0 : (index >= dates.count ? dates.count : index + 1)
    let previous = dates.prefix(split).compactMap { $0 }.last
    let next = dates.dropFirst(split).compactMap { $0 }.first
    return suggestion(on: day, previous: previous, next: next, now: now, calendar: calendar)
  }
}
