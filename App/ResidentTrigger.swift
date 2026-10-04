import Foundation

/// When a resident agent works on its own.
enum ResidentTrigger: String, Codable, CaseIterable, Identifiable {
  case dailyMorning
  case weeklyMonday
  case afterMeeting

  var id: Self { self }

  var label: String {
    switch self {
    case .dailyMorning: "毎朝 8:00"
    case .weeklyMonday: "毎週月曜 9:00"
    case .afterMeeting: "会議の要約ができたとき"
    }
  }

  /// The most recent time this trigger fell due, before `now`; nil for one
  /// that runs on an event rather than a clock.
  func lastDue(before now: Date, calendar: Calendar = .current) -> Date? {
    switch self {
    case .dailyMorning:
      let today = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
      return today <= now ? today : calendar.date(byAdding: .day, value: -1, to: today)
    case .weeklyMonday:
      var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
      components.weekday = 2
      components.hour = 9
      guard let monday = calendar.date(from: components) else { return nil }
      return monday <= now ? monday : calendar.date(byAdding: .weekOfYear, value: -1, to: monday)
    case .afterMeeting:
      return nil
    }
  }

  /// The next time this trigger falls due after `now`.
  func nextDue(after now: Date, calendar: Calendar = .current) -> Date? {
    guard let last = lastDue(before: now, calendar: calendar) else { return nil }
    switch self {
    case .dailyMorning: return calendar.date(byAdding: .day, value: 1, to: last)
    case .weeklyMonday: return calendar.date(byAdding: .weekOfYear, value: 1, to: last)
    case .afterMeeting: return nil
    }
  }
}

extension ResidentTrigger {
  /// How late a clock run may still be posted.
  var lateWindow: TimeInterval {
    switch self {
    case .dailyMorning: 10 * 3_600
    case .weeklyMonday: 3 * 86_400
    case .afterMeeting: 0
    }
  }
}
