import Foundation

struct ReviewPeriod: Hashable {
  var start: Date
  var end: Date

  func contains(_ date: Date) -> Bool { date >= start && date < end }

  var label: String {
    let lastDay = end.addingTimeInterval(-1)
    let startLabel = start.formatted(date: .abbreviated, time: .omitted)
    if Calendar.current.isDate(start, inSameDayAs: lastDay) { return startLabel }
    return "\(startLabel)〜\(lastDay.formatted(date: .abbreviated, time: .omitted))"
  }

  static func day(_ date: Date, calendar: Calendar = .current) -> ReviewPeriod {
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
    return ReviewPeriod(start: start, end: end)
  }

  static func week(_ date: Date, calendar: Calendar = .current) -> ReviewPeriod {
    guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return day(date, calendar: calendar) }
    return ReviewPeriod(start: interval.start, end: interval.end)
  }

  static func parse(start: String, end: String) -> ReviewPeriod? {
    guard let first = parseDay(start), let last = parseDay(end), last >= first,
          let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: last),
          let days = Calendar.current.dateComponents([.day], from: first, to: exclusiveEnd).day,
          days <= 366 else { return nil }
    return ReviewPeriod(start: first, end: exclusiveEnd)
  }

  static func parseDay(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
    return date
  }
}
