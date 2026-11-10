import Foundation
import SQLite3

@main
@MainActor
struct TaskProposalExecutionChecks {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memora-task-proposals-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for cloud in [false, true] {
      try await meetingFlow(root: root, cloud: cloud)
      try await declinesAndCancels(root: root, cloud: cloud)
      try await rejectsChangedApproval(root: root, cloud: cloud)
    }
    try await rejectsInvalidInput(root: root)
    try await deduplicates(root: root)
    print("TaskProposalExecutionChecks: passed (production read/agent loop/task proposals/approval waiter/SQLite reopen/list; edited selection, decline/cancel, policy/source/privacy/workspace races, malformed and forged IDs, failed atomic save, duplicate and replay rejection; model responses/registry assembly/OS services are fixtures, no network)")
  }

  static func fixture(root: URL, cloud: Bool) throws -> (MemoraModel, Meeting, URL) {
    let url = root.appendingPathComponent(UUID().uuidString + ".sqlite")
    let model = try MemoraModel(storeURL: url)
    var privacy = RecordPrivacy(classification: .personal)
    privacy.allowsCloudAI = true
    let meeting = Meeting(title: "架空の進捗会議", participantIDs: nil, privacy: privacy,
      summary: "見積書を確認する。未決事項は次回整理する。", transcript: ["担当と期限は未定です。"],
      decisions: ["見積書を確認する"], openQuestions: ["担当者と期限は未定"])
    model.meetings = [meeting]
    precondition(model.persistNow(model.meetings, forKey: MemoraModel.StorageKey.meetings))
    precondition(model.persistNow(model.tasks, forKey: MemoraModel.StorageKey.tasks))
    for tool in [AgentTool.addTasks, .readRecord, .listTasks] {
      _ = model.fixtureRegistry.register(AIToolDefinition(id: "memora:" + tool.rawValue, name: tool.rawValue,
        summary: tool.summary, inputSchema: try JSONSerialization.data(withJSONObject: tool.inputSchema),
        provider: .memora, requiredPermissions: [], risk: tool == .addTasks ? .write : .read,
        isAvailable: true, isEnabled: true))
    }
    model.agentPluginPolicies[model.message.id] = AIPluginExecutionPolicy(pluginIDs: ["skill:fixture"],
      toolIDs: ["memora:add_tasks", "memora:read_record", "memora:list_tasks"], recordIDs: [meeting.id], limitsRecordReads: true)
    if cloud {
      model.message.cloudProvenance = model.newCloudProvenance(references: [])
      model.message.cloudAuthorizationTargets = []
    }
    return (model, meeting, url)
  }

  static func call(for meeting: Meeting) -> AgentToolCall {
    AgentToolCall(id: UUID().uuidString, name: "add_tasks", arguments: ["tasks": [
      ["title": "見積書を確認する", "detail": "会議の決定事項", "meeting_id": meeting.id.uuidString],
      ["title": "未決事項を整理する", "meeting_id": meeting.id.uuidString]
    ]])
  }

  static func meetingFlow(root: URL, cloud: Bool) async throws {
    let (model, meeting, url) = try fixture(root: root, cloud: cloud)
    let messageID = model.message.id
    let proposal = call(for: meeting)
    let read = AgentToolCall(id: "read", name: "read_record", arguments: ["id": meeting.id.uuidString])
    let list = AgentToolCall(id: "list", name: "list_tasks", arguments: [:])
    let purpose: RecordAccessPolicy.Purpose = cloud ? .cloudAI : .onDeviceAI
    var responses = [AgentTurn(text: "", toolCalls: [read]), AgentTurn(text: "", toolCalls: [proposal]),
      AgentTurn(text: "", toolCalls: [list]), AgentTurn(text: "承認した1件を保存しました。", toolCalls: [])]
    var outcomes: [AgentToolOutcome] = []
    let operation = Task {
      await AgentConversationLoop.run(isAuthorized: { model.currentTeamID == nil }, next: {
        if responses.count == 3 {
          precondition(outcomes.last?.text.contains("担当と期限は未定") == true)
          precondition(outcomes.last?.text.contains(meeting.summary) == true)
        }
        return responses.removeFirst()
      }, execute: { toolCall in
        if toolCall.tool == .addTasks {
          return await model.addTasksTool(toolCall, messageID: messageID, scope: .all)
        }
        return model.automaticRecordTool(toolCall, messageID: messageID, purpose: purpose)!
      }, accept: { _, results in outcomes.append(contentsOf: results.map(\.outcome)) })
    }
    let approval = await awaitingApproval(model)
    precondition(model.tasks.isEmpty && approval.taskDrafts?.count == 2)
    try assertStored(url, equals: [])
    var edited = approval.taskDrafts!
    edited[0].title = "承認画面で修正した見積書確認"
    edited[0].detail = "利用者が確認した詳細"
    edited[1].isSelected = false
    model.approvedAgentTaskDrafts[messageID] = edited
    precondition(!model.agentApprovalWaiter.resolve(true, id: UUID()))
    precondition(model.agentApprovalWaiter.resolve(true, id: approval.id))
    precondition(!model.agentApprovalWaiter.resolve(true, id: approval.id))
    let result = await operation.value
    precondition(result.text == "承認した1件を保存しました。" && outcomes.count == 3 && outcomes.allSatisfy { !$0.isError })
    precondition(outcomes[0].dataChange == .none && outcomes[1].dataChange == .committed && outcomes[2].dataChange == .none)
    let task = model.tasks[0]
    precondition(model.tasks.count == 1 && task.id == edited[0].id && task.title == edited[0].title)
    precondition(task.detail == edited[0].detail && task.meetingID == meeting.id && task.assignee == nil && task.dueDate == nil)
    precondition(model.message.createdTaskIDs == [task.id] && model.message.interfaceTaskIDs.contains(task.id))
    precondition(outcomes.last?.text.contains(task.title) == true)
    try assertStored(url, equals: model.tasks)
    let repeated = await model.addTasksTool(proposal, messageID: messageID, scope: .all)
    precondition(repeated.isError && model.pendingAgentApproval == nil && model.tasks == [task])
    precondition(model.approvedAgentTaskDrafts.isEmpty)
  }

  static func declinesAndCancels(root: URL, cloud: Bool) async throws {
    for mode in 0..<3 {
      let (model, meeting, url) = try fixture(root: root, cloud: cloud)
      let operation = Task { await model.addTasksTool(call(for: meeting), messageID: model.message.id, scope: .all) }
      let approval = await awaitingApproval(model)
      model.approvedAgentTaskDrafts[model.message.id] = approval.taskDrafts
      if mode == 0 { model.agentApprovalWaiter.resolve(false, id: approval.id) }
      else {
        if mode == 2 { model.agentApprovalWaiter.resolve(true, id: approval.id) }
        operation.cancel()
      }
      _ = await operation.value
      precondition(model.tasks.isEmpty && model.pendingAgentApproval == nil && model.approvedAgentTaskDrafts.isEmpty)
      try assertStored(url, equals: [])
    }
  }

  static func rejectsChangedApproval(root: URL, cloud: Bool) async throws {
    for mode in 0..<18 {
      let (model, meeting, url) = try fixture(root: root, cloud: cloud)
      let messageID = model.message.id
      let operation = Task { await model.addTasksTool(call(for: meeting), messageID: messageID, scope: .projects) }
      // Keep the production scope selector in play; membership changes below must fail.
      model.meetings[0].spaceID = UUID()
      let approval = await awaitingApproval(model)
      model.approvedAgentTaskDrafts[messageID] = approval.taskDrafts
      switch mode {
      case 0: model.agentPluginPolicies.removeValue(forKey: messageID)
      case 1: model.agentPluginPolicies[messageID]?.toolIDs = []
      case 2: model.pluginPermitted = false
      case 3: model.fixtureRegistry.tools["memora:add_tasks"]?.isEnabled = false
      case 4: model.currentTeamID = "other"
      case 5: model.isRestoring = true
      case 6: model.isStoreProtected = true
      case 7: model.hasMessage = false
      case 8: model.meetings = []
      case 9: model.meetings[0].summary = "確認中に変更された決定"
      case 10: model.meetings[0].privacy.allowsCloudAI = false
      case 11: model.meetings[0].spaceID = nil
      case 12: model.approvedAgentTaskDrafts[messageID]?[0].id = UUID()
      case 13: model.approvedAgentTaskDrafts[messageID]?[0].meetingID = UUID()
      case 14: model.approvedAgentTaskDrafts[messageID] = []
      case 15: model.approvedAgentTaskDrafts.removeValue(forKey: messageID)
      case 16: model.rejectWrites = true
      default: try executeSQL("CREATE TRIGGER fail_tasks BEFORE INSERT ON documents WHEN NEW.key='tasks' BEGIN SELECT RAISE(ABORT, 'save failure'); END;", at: url)
      }
      model.agentApprovalWaiter.resolve(true, id: approval.id)
      let outcome = await operation.value
      // Source/privacy changes may invalidate the cloud approval itself first.
      precondition(outcome.isError || model.message.agentSteps.last?.state == .declined)
      precondition(model.tasks.isEmpty && model.message.createdTaskIDs.isEmpty && model.approvedAgentTaskDrafts.isEmpty && !model.message.didChangeData)
      try assertStored(url, equals: [])
    }
  }

  static func rejectsInvalidInput(root: URL) async throws {
    for mode in 0..<7 {
      let (model, meeting, url) = try fixture(root: root, cloud: true)
      var proposal = call(for: meeting)
      switch mode {
      case 0: proposal.arguments = ["tasks": [["title": "候補", "meeting_id": "not-a-uuid"]]]
      case 1: proposal.arguments = ["tasks": [["title": "候補", "meeting_id": UUID().uuidString]]]
      case 2: proposal.arguments = ["tasks": [["title": "候補", "execute": "untrusted"]]]
      case 3: proposal.arguments = ["tasks": [["title": ""]]]
      case 4: model.agentPluginPolicies[model.message.id]?.recordIDs = []
      case 5: model.currentTeamID = "team"
      default: model.meetings[0].privacy.allowsCloudAI = false
      }
      let outcome = await model.addTasksTool(proposal, messageID: model.message.id, scope: .all)
      precondition(outcome.isError && model.pendingAgentApproval == nil && model.tasks.isEmpty)
      try assertStored(url, equals: [])
    }
  }

  static func deduplicates(root: URL) async throws {
    let (model, meeting, url) = try fixture(root: root, cloud: false)
    var proposal = call(for: meeting)
    let identical = ["title": "同じ候補", "meeting_id": meeting.id.uuidString]
    proposal.arguments = ["tasks": [identical, identical]]
    let operation = Task { await model.addTasksTool(proposal, messageID: model.message.id, scope: .all) }
    let approval = await awaitingApproval(model)
    model.approvedAgentTaskDrafts[model.message.id] = approval.taskDrafts
    model.agentApprovalWaiter.resolve(true, id: approval.id)
    let outcome = await operation.value
    precondition(!outcome.isError && model.tasks.count == 1 && outcome.text.contains("1件は追加していません") && outcome.dataChange == .committed)
    try assertStored(url, equals: model.tasks)
    model.agentBlockedExternalTools.removeAll()
    let retry = Task { await model.addTasksTool(proposal, messageID: model.message.id, scope: .all) }
    let again = await awaitingApproval(model)
    model.approvedAgentTaskDrafts[model.message.id] = again.taskDrafts
    model.agentApprovalWaiter.resolve(true, id: again.id)
    let unchanged = await retry.value
    precondition(!unchanged.isError && unchanged.dataChange == .none && model.tasks.count == 1)
    try assertStored(url, equals: model.tasks)
  }

  static func awaitingApproval(_ model: MemoraModel) async -> AgentApproval {
    for _ in 0..<10_000 {
      if let approval = model.pendingAgentApproval { return approval }
      await Task.yield()
    }
    preconditionFailure("Approval was not presented")
  }

  static func assertStored(_ url: URL, equals expected: [MemoraTask]) throws {
    let actual = try stored(url)
    precondition(actual == expected, "SQLite tasks differ")
  }

  static func stored(_ url: URL) throws -> [MemoraTask] {
    let store = LocalStore(fileURL: url)
    try store.prepare()
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.tasks) else { preconditionFailure("Missing tasks") }
    return try JSONDecoder().decode([MemoraTask].self, from: data)
  }

  static func executeSQL(_ sql: String, at url: URL) throws {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw LocalStore.StoreError.open(0) }
    defer { sqlite3_close(connection) }
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw LocalStore.StoreError.statement(0) }
  }
}
