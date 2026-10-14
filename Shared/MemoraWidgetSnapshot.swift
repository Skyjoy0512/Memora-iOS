import Foundation

struct MemoraWidgetSnapshot: Codable, Equatable, Sendable {
  var generatedAt: Date
  var day: Date
  var openTaskCount: Int
  var recordCount: Int
  var nextEventAt: Date?
  var projects: [Project]

  struct Project: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var openTaskCount: Int
    var lastRecordAt: Date?
  }

  func isValid(at now: Date, calendar: Calendar = .current) -> Bool {
    guard generatedAt <= now.addingTimeInterval(60), now.timeIntervalSince(generatedAt) <= 8 * 3_600,
          calendar.isDate(day, inSameDayAs: now), calendar.isDate(generatedAt, inSameDayAs: day),
          (0...1_000_000).contains(openTaskCount),
          (0...1_000_000).contains(recordCount), projects.count <= 20,
          Set(projects.map(\.id)).count == projects.count else { return false }
    if let nextEventAt {
      guard nextEventAt >= generatedAt, calendar.isDate(nextEventAt, inSameDayAs: day) else { return false }
    }
    return projects.allSatisfy {
      !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80
        && (0...1_000_000).contains($0.openTaskCount) && ($0.lastRecordAt.map { $0 <= now.addingTimeInterval(60) } ?? true)
    }
  }
}
