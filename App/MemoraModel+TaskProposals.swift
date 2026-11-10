import Foundation

extension MemoraModel {
  func addTasksTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope) async -> AgentToolOutcome {
    defer { approvedAgentTaskDrafts.removeValue(forKey: messageID) }
    guard taskProposalContextIsCurrent(call, messageID: messageID) else { return AgentToolOutcome(text: "保存先を確認できないため追加できません。", isError: true) }
    let drafts: [AgentTaskDraft]
    do { drafts = try AgentTaskDraft.parse(call.objects("tasks")) }
    catch { return AgentToolOutcome(text: "候補のタイトル・詳細・担当・期限を確認してください。タスクは追加していません。", isError: true) }
    let scopedMeetingIDs = Set(Self.meetings(in: scope, from: meetings).map(\.id))
    guard drafts.allSatisfy({ $0.meetingID.map(scopedMeetingIDs.contains) ?? true }) else {
      return AgentToolOutcome(text: "対象外または存在しない会議が指定されています。タスクは追加していません。", isError: true)
    }
    let workspaceID = currentTeamID
    let policy = agentPluginPolicies[messageID]
    let sourceIDs = Set(drafts.compactMap(\.meetingID))
    // The approval covers these source revisions and this selection, not a
    // different record or a policy that disappeared while the card was open.
    let originals = meetings.filter { sourceIDs.contains($0.id) }
    guard sourceIDs.count == originals.count,
          originals.allSatisfy({ taskProposalSourceIsAllowed($0, messageID: messageID) }) else {
      return AgentToolOutcome(text: "参照範囲または記録の権限を確認できません。タスクは追加していません。", isError: true)
    }
    let stepID = beginAgentStep(AgentStep(icon: .checklist, title: "タスク候補を確認しています", detail: "確認待ち"), on: messageID)
    let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .checklist,
      title: "タスクを\(drafts.count)件追加", lines: [], confirmTitle: "追加", taskDrafts: drafts))
    guard approved, !Task.isCancelled else {
      finishAgentStep(stepID, on: messageID, state: .declined)
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      return Self.declinedOutcome
    }
    let allowedIDs = Set(Self.meetings(in: scope, from: meetings).map(\.id))
    guard currentTeamID == workspaceID, agentPluginPolicies[messageID] == policy,
          taskProposalContextIsCurrent(call, messageID: messageID),
          originals.allSatisfy({ original in
            meeting(id: original.id) == original && taskProposalSourceIsAllowed(original, messageID: messageID)
          }),
          let edited = approvedAgentTaskDrafts.removeValue(forKey: messageID),
          let selected = AgentTaskDraft.validatedSelection(edited, originals: drafts, allowedMeetingIDs: allowedIDs),
          !selected.isEmpty else {
      finishAgentStep(stepID, on: messageID, state: .failed)
      return AgentToolOutcome(text: "候補・権限・ワークスペースが変わりました。タスクは追加していません。", isError: true)
    }
    var existing = tasks.filter { !$0.isCompleted }
    var additions: [MemoraTask] = []
    var skipped = 0
    for draft in selected {
      let candidate = MemoraTask(id: draft.id, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
        meetingID: draft.meetingID, assignee: draft.assignee.isEmpty ? nil : draft.assignee,
        dueDate: draft.dueDate, isCompleted: false, detail: draft.detail)
      if existing.contains(where: { Self.matchesTaskProposal($0, candidate) }) { skipped += 1; continue }
      additions.append(candidate)
      existing.append(candidate)
    }
    if !additions.isEmpty, !insertTasks(additions) {
      finishAgentStep(stepID, on: messageID, state: .failed)
      agentBlockedExternalTools[messageID, default: []].insert(call.name)
      return AgentToolOutcome(text: "保存できませんでした。タスクは追加していません。", isError: true)
    }
    // One approved batch per reply prevents another model turn from repeating it.
    agentBlockedExternalTools[messageID, default: []].insert(call.name)
    updateAgentMessage(messageID) { $0.createdTaskIDs.append(contentsOf: additions.map(\.id)) }
    finishAgentStep(stepID, on: messageID, state: .done, detail: "\(additions.count)件")
    let duplicateNote = skipped > 0 ? " 同じ内容の未完了タスク\(skipped)件は追加していません。" : ""
    return AgentToolOutcome(text: "承認された内容でタスクを\(additions.count)件追加しました。" + duplicateNote
      + " 候補は利用者が編集している場合があります。完了報告はこの件数を使い、編集前のタイトル・担当・期限を保存済みと報告しないでください。", dataChange: additions.isEmpty ? .none : .committed)
  }

  private static func matchesTaskProposal(_ left: MemoraTask, _ right: MemoraTask) -> Bool {
    left.title == right.title && left.detail == right.detail && left.assignee == right.assignee
      && left.meetingID == right.meetingID && left.dueDate == right.dueDate
  }

  private func taskProposalContextIsCurrent(_ call: AgentToolCall, messageID: UUID) -> Bool {
    guard !Task.isCancelled, !isRestoring, currentTeamID == nil, isStoreWritable(),
          !agentBlockedExternalTools[messageID, default: []].contains(call.name),
          let message = agentMessage(messageID), pluginCallIsPermitted(call, messageID: messageID),
          toolRegistry().permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID]) else { return false }
    if let policy = agentPluginPolicies[messageID], !personPolicyIsCurrent(policy) { return false }
    return message.cloudProvenance == nil || isCloudSessionAuthorized(messageID)
  }

  private func taskProposalSourceIsAllowed(_ record: Meeting, messageID: UUID) -> Bool {
    if let policy = agentPluginPolicies[messageID], policy.limitsRecordReads, !policy.recordIDs.contains(record.id) { return false }
    let purpose: RecordAccessPolicy.Purpose = agentMessage(messageID)?.cloudProvenance == nil ? .onDeviceAI : .cloudAI
    return allowsRecordAccess(record.id, purpose: purpose)
  }
}
