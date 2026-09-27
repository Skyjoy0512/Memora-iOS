import Foundation

/// One next step found in a meeting. Owner and due are kept as the meeting
/// said them; nil means the meeting did not say, never a guess.
struct SummaryActionItem: Hashable, Codable {
  var title: String
  var detail: String = ""
  var owner: String?
  var due: String?

  /// The words the engines use for "not said". Treated as no value, so a task
  /// never gets "未定" as its assignee.
  static let unknownMarkers: Set<String> = [
    "", "-", "—", "未定", "未指定", "不明", "なし", "記載なし", "期日未記載", "未記載", "tbd", "unknown", "n/a"
  ]

  /// Nil for anything that means "not said", with a leading @ removed.
  static func normalized(_ value: String?) -> String? {
    guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    if value.hasPrefix("@") || value.hasPrefix("＠") { value.removeFirst() }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return unknownMarkers.contains(value.lowercased()) ? nil : value
  }

  /// The due date, only when the meeting named a calendar date. Relative words
  /// such as 来週 are left alone rather than turned into a guessed day.
  func dueDate(relativeTo meetingDate: Date, calendar: Calendar = .current) -> Date? {
    guard let due = Self.normalized(due) else { return nil }
    let digits = due.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? due

    if let match = digits.firstMatch(of: #/(\d{4})[-\/年](\d{1,2})[-\/月](\d{1,2})/#) {
      return calendar.date(from: DateComponents(
        year: Int(match.1), month: Int(match.2), day: Int(match.3)
      ))
    }
    if let match = digits.firstMatch(of: #/(\d{1,2})[\/月](\d{1,2})日?/#) {
      let meetingYear = calendar.component(.year, from: meetingDate)
      guard var date = calendar.date(from: DateComponents(
        year: meetingYear, month: Int(match.1), day: Int(match.2)
      )) else { return nil }
      // A month already well behind the meeting means the next year's date.
      if date < meetingDate.addingTimeInterval(-60 * 24 * 60 * 60),
         let next = calendar.date(byAdding: .year, value: 1, to: date) {
        date = next
      }
      return date
    }
    return nil
  }
}
