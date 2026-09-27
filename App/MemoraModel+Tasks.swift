import Foundation

extension MemoraModel {
  func toggleTask(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].isCompleted.toggle()
    tasks[index].completedAt = tasks[index].isCompleted ? .now : nil
    persistTasks()
    TaskReminderScheduler.refresh(tasks[index])
  }

  func updateTask(
    _ id: UUID,
    title: String,
    assignee: String,
    dueDate: Date?,
    meetingID: UUID?,
    remindsAtDue: Bool? = nil,
    reminderTime: Date? = nil
  ) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }
    let trimmedAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)

    tasks[index].title = trimmedTitle
    tasks[index].assignee = trimmedAssignee.isEmpty ? nil : trimmedAssignee
    tasks[index].dueDate = dueDate
    tasks[index].meetingID = meetingID
    if let remindsAtDue {
      tasks[index].remindsAtDue = remindsAtDue
    }
    tasks[index].reminderTime = reminderTime
    persistTasks()
    // A due-date change or a completion moves or clears the reminder.
    TaskReminderScheduler.refresh(tasks[index])
  }

  /// Changes just the due date, from the task list's long-press menu.
  func setTaskDueDate(_ id: UUID, to date: Date?) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].dueDate = date
    persistTasks()
    TaskReminderScheduler.refresh(tasks[index])
  }

  func deleteTask(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    let removed = tasks.remove(at: index)
    persistTasks()
    TaskReminderScheduler.cancel(taskID: id)
    scheduleUndo(
      UndoAction(message: "「\(removed.title)」を削除しました") { [weak self] in
        self?.restoreTask(removed, at: index)
      } finalize: {}
    )
  }

  /// Puts a removed task back where it was, so an undo restores its order too.
  private func restoreTask(_ task: MemoraTask, at index: Int) {
    let position = min(index, tasks.count)
    tasks.insert(task, at: position)
    persistTasks()
    TaskReminderScheduler.refresh(task)
  }

  func addTask(
    title: String,
    assignee: String,
    dueDate: Date?,
    meetingID: UUID? = nil,
    remindsAtDue: Bool = false,
    reminderTime: Date? = nil
  ) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }
    let trimmedAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
    let task = MemoraTask(
      id: UUID(),
      title: trimmedTitle,
      meetingID: meetingID,
      assignee: trimmedAssignee.isEmpty ? nil : trimmedAssignee,
      dueDate: dueDate,
      isCompleted: false,
      remindsAtDue: remindsAtDue,
      reminderTime: reminderTime
    )
    tasks.insert(task, at: 0)
    persistTasks()
    TaskReminderScheduler.refresh(task)
  }
}
