import Foundation

extension MemoraModel {
  func task(id: UUID) -> MemoraTask? { taskIndex.element(id, in: tasks) }

  var ownTasks: [MemoraTask] {
    TaskOwnership.ownedTasks(tasks, names: [profile.name, account?.displayName ?? ""])
  }

  func isOwnTask(_ task: MemoraTask) -> Bool {
    TaskOwnership.isMine(task, names: [profile.name, account?.displayName ?? ""])
  }

  /// Records the person's decision on an owner the summary could not confirm, so
  /// the name rule does not decide it later.
  @discardableResult
  func confirmTaskOwner(_ id: UUID, isMine: Bool) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(),
          let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
    var candidate = tasks
    candidate[index].ownedByMe = isMine
    candidate[index].ownerNeedsConfirmation = nil
    if isMine { candidate[index].assignee = nil }
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return false }
    tasks = candidate
    return true
  }

  func toggleTask(_ id: UUID) {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    var candidate = tasks
    candidate[index].isCompleted.toggle()
    candidate[index].completedAt = candidate[index].isCompleted ? .now : nil
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return }
    tasks = candidate
    TaskReminderScheduler.refresh(tasks[index])
  }

  @discardableResult
  func updateTask(
    _ id: UUID,
    title: String,
    assignee: String,
    dueDate: Date?,
    meetingID: UUID?,
    detail: String? = nil,
    workDate: Date?,
    progress: TaskProgress? = nil,
    remindsAtDue: Bool? = nil,
    reminderTime: Date? = nil,
    ownedByMe: Bool? = nil,
    relationships: TaskRelationships? = nil
  ) -> Bool {
    guard !isRestoring, currentTeamID == nil, let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return false }
    let trimmedAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
    if let relationships,
       !TaskHierarchy.canParent(id, under: relationships.parentID, tasks: tasks) { return false }

    var candidate = tasks
    candidate[index].title = trimmedTitle
    if candidate[index].meetingID != meetingID, candidate[index].meetingID != nil {
      var privacy = candidate[index].privacy ?? RecordPrivacy()
      if let parent = candidate[index].meetingID.flatMap({ self.meeting(id: $0) }) {
        let sensitivity: SummarySensitivity = switch parent.effectivePrivacy.classification {
        case .unknown, .general: .general
        case .personal: .personal
        case .sensitive: .sensitive
        }
        privacy.protect(sensitivity)
      }
      privacy.revokeExternalPermissions()
      candidate[index].privacy = privacy
    }
    if let ownedByMe {
      candidate[index].ownedByMe = ownedByMe
      // Editing the owner settles whatever the summary left open.
      candidate[index].ownerNeedsConfirmation = nil
    } else if trimmedAssignee != (candidate[index].assignee ?? "") {
      candidate[index].ownedByMe = nil
      candidate[index].ownerNeedsConfirmation = nil
    }
    if let relationships { candidate[index].relationships = relationships }
    if relationships == nil, trimmedAssignee != (tasks[index].assignee ?? "") {
      candidate[index].relationships.assigneePersonID = nil
    }
    if candidate[index].ownedByMe == true { candidate[index].relationships.assigneePersonID = nil }
    let selectedID = candidate[index].relationships.assigneePersonID
    if let selectedID, person(id: selectedID) == nil, selectedID != tasks[index].relationships.assigneePersonID { return false }
    candidate[index].assignee = selectedID.flatMap { person(id: $0)?.name } ?? (trimmedAssignee.isEmpty ? nil : trimmedAssignee)
    if selectedID != tasks[index].relationships.assigneePersonID {
      candidate[index].privacy = taskPrivacyAfterPersonChange(tasks[index])
    }
    candidate[index].dueDate = dueDate
    candidate[index].meetingID = meetingID
    if let detail { candidate[index].detail = detail.trimmingCharacters(in: .whitespacesAndNewlines) }
    candidate[index].workDate = workDate.map { Calendar.current.startOfDay(for: $0) }
    if let progress { candidate[index].progress = progress }
    if let remindsAtDue {
      candidate[index].remindsAtDue = remindsAtDue
    }
    candidate[index].reminderTime = reminderTime
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return false }
    tasks = candidate
    // A due-date change or a completion moves or clears the reminder.
    TaskReminderScheduler.refresh(tasks[index])
    return true
  }

  /// Changes just the due date, from the task list's long-press menu.
  func setTaskDueDate(_ id: UUID, to date: Date?) {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    var candidate = tasks
    candidate[index].dueDate = date
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return }
    tasks = candidate
    TaskReminderScheduler.refresh(tasks[index])
  }

  func setTaskWorkDate(_ id: UUID, to date: Date?) {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    var candidate = tasks
    candidate[index].workDate = date.map { Calendar.current.startOfDay(for: $0) }
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return }
    tasks = candidate
  }

  @discardableResult
  func deleteTask(_ id: UUID) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
    guard !tasks.contains(where: { $0.relationships.parentID == id }) else {
      deletionFailureMessage = "子課題が残っています。子課題の親を変更するか、子課題を先に削除してください。"
      return false
    }
    var candidate = tasks
    let removed = candidate.remove(at: index)
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return false }
    tasks = candidate
    TaskReminderScheduler.cancel(taskID: id)
    scheduleUndo(
      UndoAction(message: "「\(removed.title)」を削除しました") { [weak self] in
        self?.restoreTask(removed, at: index) ?? false
      } finalize: {}
    )
    return true
  }

  /// Puts a removed task back where it was, so an undo restores its order too.
  private func restoreTask(_ task: MemoraTask, at index: Int) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return false }
    if let existing = tasks.first(where: { $0.id == task.id }) {
      guard existing == task else {
        deletionFailureMessage = "同じIDのタスクが更新されているため、上書きせずに復元を止めました。"
        return false
      }
      return true
    }
    var candidate = tasks
    candidate.insert(task, at: min(max(0, index), tasks.count))
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return false }
    tasks = candidate
    TaskReminderScheduler.refresh(task)
    return true
  }

  @discardableResult
  func addTask(
    title: String,
    assignee: String,
    dueDate: Date?,
    meetingID: UUID? = nil,
    remindsAtDue: Bool = false,
    reminderTime: Date? = nil,
    ownedByMe: Bool? = nil,
    parentID: UUID? = nil,
    detail: String = "",
    assigneePersonID: UUID? = nil
  ) -> Bool {
    guard !isRestoring, currentTeamID == nil else { return false }
    if let assigneePersonID { guard ownedByMe != true, person(id: assigneePersonID) != nil else { return false } }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return false }
    let trimmedAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
    let identifier = UUID()
    guard TaskHierarchy.canParent(identifier, under: parentID, tasks: tasks) else { return false }
    let task = MemoraTask(
      id: identifier,
      title: trimmedTitle,
      meetingID: meetingID,
      assignee: trimmedAssignee.isEmpty ? nil : trimmedAssignee,
      dueDate: dueDate,
      isCompleted: false,
      remindsAtDue: remindsAtDue,
      reminderTime: reminderTime,
      ownedByMe: ownedByMe,
      relationships: TaskRelationships(parentID: parentID, assigneePersonID: assigneePersonID)
    )
    var taskWithNote = task
    if let assigneePersonID {
      taskWithNote.assignee = person(id: assigneePersonID)?.name
      var privacy = RecordPrivacy(); privacy.protect(.personal)
      taskWithNote.privacy = privacy
    }
    taskWithNote.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    return insertTasks([taskWithNote])
  }

  @discardableResult
  func insertTasks(_ additions: [MemoraTask]) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return false }
    let ids = Set(additions.map(\.id))
    guard !additions.isEmpty, ids.count == additions.count,
          ids.isDisjoint(with: tasks.map(\.id)) else { return false }
    var candidate = tasks
    candidate.insert(contentsOf: additions, at: 0)
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return false }
    tasks = candidate
    for task in additions { TaskReminderScheduler.refresh(task) }
    return true
  }

  func taskPrivacyAfterPersonChange(_ task: MemoraTask) -> RecordPrivacy {
    var value = privacy(for: .task(task.id)) ?? task.privacy ?? RecordPrivacy()
    value.protect(.personal)
    value.revokeExternalPermissions()
    return value
  }

}
