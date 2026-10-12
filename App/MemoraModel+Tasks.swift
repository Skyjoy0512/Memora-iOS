import Foundation

extension MemoraModel {
  func isOwnTask(_ task: MemoraTask) -> Bool {
    TaskOwnership.isMine(task, names: [profile.name, account?.displayName ?? ""])
  }

  func toggleTask(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
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
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
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
    } else if trimmedAssignee != (candidate[index].assignee ?? "") {
      candidate[index].ownedByMe = nil
    }
    if let relationships { candidate[index].relationships = relationships }
    candidate[index].assignee = trimmedAssignee.isEmpty ? nil : trimmedAssignee
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
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    var candidate = tasks
    candidate[index].dueDate = date
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return }
    tasks = candidate
    TaskReminderScheduler.refresh(tasks[index])
  }

  func setTaskWorkDate(_ id: UUID, to date: Date?) {
    guard isStoreWritable(), let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    var candidate = tasks
    candidate[index].workDate = date.map { Calendar.current.startOfDay(for: $0) }
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return }
    tasks = candidate
  }

  @discardableResult
  func deleteTask(_ id: UUID) -> Bool {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
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
        self?.restoreTask(removed, at: index)
      } finalize: {}
    )
    return true
  }

  /// Puts a removed task back where it was, so an undo restores its order too.
  private func restoreTask(_ task: MemoraTask, at index: Int) {
    let position = min(index, tasks.count)
    guard !tasks.contains(where: { $0.id == task.id }) else { return }
    var candidate = tasks
    candidate.insert(task, at: position)
    guard persistNow(candidate, forKey: StorageKey.tasks) else { return }
    tasks = candidate
    TaskReminderScheduler.refresh(task)
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
    detail: String = ""
  ) -> Bool {
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
      relationships: TaskRelationships(parentID: parentID)
    )
    var taskWithNote = task
    taskWithNote.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    return insertTasks([taskWithNote])
  }

  @discardableResult
  func insertTasks(_ additions: [MemoraTask]) -> Bool {
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

  /// Files a summary's actions in the tasks tab, tied to their record. An
  /// action whose title the record already has a task for is skipped, so
  /// generating again does not duplicate tasks or touch ones already edited.
  /// Owner and due date are only set when the meeting said them.
  @discardableResult
  func addExtractedTasks(_ actions: [SummaryActionItem], meetingID: UUID, meetingDate: Date) -> Int {
    var existing = Set(tasks(forMeeting: meetingID).map { SummaryResponseParser.taskKey($0.title) })
    var added: [MemoraTask] = []
    for action in actions {
      let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty, existing.insert(SummaryResponseParser.taskKey(title)).inserted else { continue }
      added.append(MemoraTask(
        id: UUID(),
        title: title,
        meetingID: meetingID,
        assignee: SummaryActionItem.normalized(action.owner),
        dueDate: action.dueDate(relativeTo: meetingDate),
        isCompleted: false,
        detail: action.detail
      ))
    }
    guard !added.isEmpty else { return 0 }
    // Newest first, like a task added by hand, keeping the meeting's order.
    return insertTasks(added) ? added.count : 0
  }
}
