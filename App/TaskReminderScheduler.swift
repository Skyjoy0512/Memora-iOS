import Foundation
import UserNotifications

/// Schedules one local notification for a task's due date, at 9:00. Nothing is
/// scheduled unless the task asks for a reminder, and the identifier is the
/// task's id so it can be replaced or removed without guessing.
extension Notification.Name {
  /// Posted when a task reminder is tapped, carrying the task's id.
  static let taskReminderTapped = Notification.Name("memoraTaskReminderTapped")
}

enum TaskReminderScheduler {
  static let taskIDKey = "taskID"

  /// The notification's identifier for a task.
  static func identifier(for taskID: UUID) -> String {
    "memora.task.\(taskID.uuidString)"
  }

  /// Asks for permission, only when a reminder is first turned on.
  static func requestAuthorization() async -> Bool {
    let center = UNUserNotificationCenter.current()
    do {
      return try await center.requestAuthorization(options: [.alert, .sound, .badge])
    } catch {
      return false
    }
  }

  /// Registers or clears the reminder for a task to match its state now.
  static func refresh(_ task: MemoraTask) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier(for: task.id)])

    guard task.remindsAtDue, !task.isCompleted, let dueDate = task.dueDate else { return }
    guard let fireDate = calendarDateAtNine(on: dueDate), fireDate > .now else { return }

    let content = UNMutableNotificationContent()
    content.title = task.title
    content.body = "今日が期限です。"
    content.sound = .default
    content.userInfo = [taskIDKey: task.id.uuidString]

    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: fireDate
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    center.add(UNNotificationRequest(identifier: identifier(for: task.id), content: content, trigger: trigger))
  }

  static func cancel(taskID: UUID) {
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: [identifier(for: taskID)])
  }

  /// Re-registers every task that wants a reminder, e.g. after a restore.
  static func refreshAll(_ tasks: [MemoraTask]) {
    for task in tasks where task.remindsAtDue {
      refresh(task)
    }
  }

  private static func calendarDateAtNine(on date: Date) -> Date? {
    Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)
  }
}
