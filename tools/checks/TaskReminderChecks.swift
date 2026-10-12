import Foundation

@main
struct TaskReminderChecks {
  static func main() {
    let id = UUID()
    precondition(TaskReminderScheduler.identifier(for: id) == "memora.task.\(id.uuidString)")
    precondition(TaskReminderScheduler.taskID(in: ["taskID": id.uuidString]) == id)
    precondition(TaskReminderScheduler.taskID(in: [:]) == nil)
    precondition(TaskReminderScheduler.taskID(in: ["taskID": "invalid"]) == nil)
    precondition(TaskReminderScheduler.taskID(in: ["taskID": 42]) == nil)
    precondition(TaskReminderScheduler.taskID(in: ["residentID": id.uuidString]) == nil)
    let calendar = Calendar.current
    let due = calendar.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: 18))!
    let chosenTime = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 16, minute: 35))!
    let scheduled = TaskReminderScheduler.fireComponents(dueDate: due, reminderTime: chosenTime)!
    precondition(scheduled.year == 2027 && scheduled.month == 1 && scheduled.day == 14)
    precondition(scheduled.hour == 16 && scheduled.minute == 35)
    let defaultTime = TaskReminderScheduler.fireComponents(dueDate: due, reminderTime: nil)!
    precondition(defaultTime.hour == 9 && defaultTime.minute == 0)
    print("TaskReminderChecks: passed (identifiers, payload validation, due day, custom/default reminder time)")
  }
}
