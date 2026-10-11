import Foundation

enum JournalActivityDays {
  static func build(recordedDays: Set<Date>, completedAt: [Date],
                    now: Date = .now, calendar: Calendar = .current) -> Set<Date> {
    recordedDays.union(completedAt.filter { $0 <= now }.map { calendar.startOfDay(for: $0) })
  }
}
