import Foundation

struct JournalBackdropSelection {
  private(set) var current: JournalBackdrop
  private var selections: [Date: JournalBackdrop]

  init(date: Date = .now, calendar: Calendar = .current) {
    let initial = JournalBackdrop.random()
    current = initial
    selections = [calendar.startOfDay(for: date): initial]
  }

  mutating func select(_ date: Date, calendar: Calendar = .current) {
    let day = calendar.startOfDay(for: date)
    let backdrop = selections[day] ?? JournalBackdrop.random(excluding: current)
    selections[day] = backdrop
    current = backdrop
  }

  mutating func shuffle(_ date: Date, calendar: Calendar = .current) {
    current = JournalBackdrop.random(excluding: current)
    selections[calendar.startOfDay(for: date)] = current
  }
}
