import Foundation

enum MemoraFormat {
  static func duration(_ interval: TimeInterval) -> String {
    let totalSeconds = max(0, Int(interval))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }

  static func relativeDate(_ date: Date) -> String {
    relativeFormatter.localizedString(for: date, relativeTo: .now)
  }

  static func dueDate(_ date: Date) -> String {
    dueDateFormatter.string(from: date)
  }

  static func meetingDate(_ date: Date) -> String {
    meetingDateFormatter.string(from: date)
  }

  private static let locale = Locale(identifier: "ja_JP")

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.unitsStyle = .short
    return formatter
  }()

  private static let dueDateFormatter = dateFormatter(template: "M月d日(E)")
  private static let meetingDateFormatter = dateFormatter(template: "M月d日(E) H:mm")

  private static func dateFormatter(template: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter
  }
}
