import Foundation

@main
struct JournalInsertionTimeChecks {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    func date(_ hour: Int, _ minute: Int = 0) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: hour, minute: minute))!
    }
    let day = date(0)
    let now = date(16)
    precondition(JournalInsertionTime.suggestion(on: day, previous: date(10), next: date(11), now: now, calendar: calendar) == date(10, 30))
    precondition(JournalInsertionTime.suggestion(on: day, previous: date(10), next: date(10), now: now, calendar: calendar) == date(10))
    precondition(JournalInsertionTime.suggestion(on: day, previous: date(11), next: date(10), now: now, calendar: calendar) == date(11))
    precondition(JournalInsertionTime.suggestion(on: day, previous: date(10), now: now, calendar: calendar) == now)
    precondition(JournalInsertionTime.suggestion(on: day, previous: date(18), now: now, calendar: calendar) == date(18, 30))
    precondition(JournalInsertionTime.suggestion(on: day, now: now, calendar: calendar) == now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
    let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
    precondition(JournalInsertionTime.suggestion(on: tomorrow, now: now, calendar: calendar) == morning)
    precondition(JournalInsertionTime.suggestion(on: day, previous: date(10), now: tomorrow, calendar: calendar) == date(10, 30))
    let end = tomorrow.addingTimeInterval(-1)
    precondition(JournalInsertionTime.suggestion(on: day, previous: date(23, 50), now: now, calendar: calendar) == end)
    precondition(JournalInsertionTime.suggestion(on: day, next: date(0, 10), now: now, calendar: calendar) == day)
    for index in [0, 1] {
      precondition(JournalInsertionTime.suggestion(on: day, after: index, dates: [date(10), nil, date(11)], now: now, calendar: calendar) == date(10, 30))
    }
    precondition(JournalInsertionTime.suggestion(on: day, after: Int.max, dates: [], now: now, calendar: calendar) == now)
    precondition(JournalInsertionTime.suggestion(on: day, after: Int.min, dates: [date(11)], now: now, calendar: calendar) == date(10, 30))
    precondition(JournalInsertionTime.suggestion(on: day, after: 0, dates: [nil], now: now, calendar: calendar) == now)
    for zone in ["America/New_York", "Europe/Berlin", "Asia/Tokyo"] {
      calendar.timeZone = TimeZone(identifier: zone)!
      for month in [3, 10, 11] {
        for dayOfMonth in [1, 8, 25, 31] {
          let selected = calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth))!
          let interval = calendar.dateInterval(of: .day, for: selected)!
          for (previous, next) in [(interval.start.addingTimeInterval(-3_600), interval.end.addingTimeInterval(3_600)),
                                   (interval.end.addingTimeInterval(-60), interval.end)] {
            let suggested = JournalInsertionTime.suggestion(on: selected, previous: previous, next: next, now: now, calendar: calendar)
            precondition(suggested >= interval.start && suggested < interval.end)
          }
        }
      }
    }
    print("JournalInsertionTimeChecks: passed (midpoint, equal/reversed, now marker exclusion, selected day, natural tail, overflow, DST and day boundaries)")
  }
}
