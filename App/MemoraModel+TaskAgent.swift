import Foundation

extension MemoraModel {
  func updateTasksTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) async -> AgentToolOutcome {
    guard isStoreWritable() else { return AgentToolOutcome(text: "保存先を確認できないため変更できません。", isError: true) }
    let workspaceID = currentTeamID
    let updates = call.objects("updates")
    guard !updates.isEmpty, updates.count <= 30 else {
      return AgentToolOutcome(text: "変更対象は1〜30件で指定してください。", isError: true)
    }
    let allowedMeetings = Self.meetings(in: scope, from: meetings)
    let allowedTasks = scope == .all ? tasks : Self.tasks(in: allowedMeetings, from: tasks)
    var originals: [MemoraTask] = []
    var seenIDs = Set<UUID>()
    var changed: [MemoraTask] = []
    var lines: [String] = []
    for update in updates {
      guard let rawID = update["id"] as? String, let id = UUID(uuidString: rawID),
            seenIDs.insert(id).inserted,
            let original = allowedTasks.first(where: { $0.id == id }) else {
        return AgentToolOutcome(text: "対象外・存在しない・重複したタスクがあります。list_tasksで対象を確認してください。", isError: true)
      }
      var candidate = original
      if let rawDate = update["work_date"] as? String {
        if rawDate.isEmpty {
          candidate.workDate = nil
        } else if let date = ReviewPeriod.parseDay(rawDate) {
          candidate.workDate = date
        } else {
          return AgentToolOutcome(text: "取り組む日はyyyy-MM-ddで指定してください。", isError: true)
        }
      }
      if let rawProgress = update["progress"] as? String {
        guard let progress = TaskProgress(rawValue: rawProgress) else {
          return AgentToolOutcome(text: "進み具合はnotStarted / inProgress / waitingです。", isError: true)
        }
        candidate.progress = progress
      }
      if let completed = update["is_completed"] as? Bool {
        candidate.isCompleted = completed
      }
      guard candidate != original else { continue }
      originals.append(original)
      changed.append(candidate)
      let before = Self.taskAgentState(original)
      let after = Self.taskAgentState(candidate)
      lines.append("\(original.title)\n変更前: \(before)\n変更後: \(after)")
    }
    guard !changed.isEmpty else { return AgentToolOutcome(text: "指定された状態と同じため、変更はありません。") }
    lines.append("期限・担当・タイトル・説明は変更しません。")
    let stepID = beginAgentStep(AgentStep(icon: .checklist, title: "タスクの変更を確認しています"), on: messageID)
    let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .checklist, title: "\(changed.count)件のタスクを更新", lines: lines, confirmTitle: "変更する"))
    guard approved, !Task.isCancelled else {
      finishAgentStep(stepID, on: messageID, state: .declined)
      return AgentToolOutcome(text: "利用者が承認しなかったため変更しませんでした。同じ操作を繰り返さないでください。")
    }
    guard currentTeamID == workspaceID,
          originals.allSatisfy({ original in tasks.first(where: { $0.id == original.id }) == original }) else {
      finishAgentStep(stepID, on: messageID, state: .failed)
      return AgentToolOutcome(text: "確認中に対象またはワークスペースが変わりました。変更せず停止しました。", isError: true)
    }
    var candidateTasks = tasks
    for var task in changed {
      guard let index = candidateTasks.firstIndex(where: { $0.id == task.id }) else { continue }
      if task.isCompleted != candidateTasks[index].isCompleted { task.completedAt = task.isCompleted ? .now : nil }
      candidateTasks[index] = task
    }
    guard persistNow(candidateTasks, forKey: StorageKey.tasks) else {
      finishAgentStep(stepID, on: messageID, state: .failed)
      return AgentToolOutcome(text: "保存できませんでした。タスクは変更していません。", isError: true)
    }
    tasks = candidateTasks
    for task in changed {
      if let saved = tasks.first(where: { $0.id == task.id }) { TaskReminderScheduler.refresh(saved) }
    }
    finishAgentStep(stepID, on: messageID, state: .done, detail: "\(changed.count)件")
    return AgentToolOutcome(text: "承認された\(changed.count)件を変更しました。期限・担当・本文はそのままです。")
  }

  private static func taskAgentState(_ task: MemoraTask) -> String {
    let state = task.isCompleted ? "完了" : task.progress.label
    let date = task.workDate?.formatted(date: .abbreviated, time: .omitted) ?? "未設定"
    return "\(state) / 取り組む日: \(date)"
  }
}
