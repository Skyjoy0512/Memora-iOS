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
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: .now)
  }

  static func dueDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.setLocalizedDateFormatFromTemplate("M月d日(E)")
    return formatter.string(from: date)
  }

  static func meetingDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.setLocalizedDateFormatFromTemplate("M月d日(E) H:mm")
    return formatter.string(from: date)
  }
}
