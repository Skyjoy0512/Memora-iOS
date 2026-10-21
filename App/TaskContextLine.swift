import Foundation

/// Work planning and progress are separate from the promised due date.
enum TaskContextLine {
  static func text(progress: TaskProgress, workDate: Date?, isCompleted: Bool) -> String? {
    guard !isCompleted else { return nil }
    var parts: [String] = []
    if progress != .notStarted { parts.append(progress.label) }
    if let workDate { parts.append("取り組む日 \(MemoraFormat.dueDate(workDate))") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}
