import Foundation
import SQLite3

@main
@MainActor
struct IntelligentUITaskExecutionChecks {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memora-interface-task-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for cloud in [false, true] {
      try await approvedFlow(root: root, cloud: cloud)
      try await declinedAndCancelled(root: root, cloud: cloud)
    }
    try await rejectsBeforeDispatch(root: root)
    try await rechecksAfterApproval(root: root)
    try await rechecksProjectMembership(root: root)
    try await validatesWholeBatch(root: root)
    print("IntelligentUITaskExecutionChecks: passed (production UI action + registry/schema/policy + approval/waiter + task update + real SQLite reopen; decline/cancel/race/stale IDs, deferred dispatch, permission/selection/scope/revision changes, failed save, atomic batch and repeat tap; registry assembly/dispatcher/reminder services are fixtures, no network)")
  }

  static func fixture(root: URL, cloud: Bool = false) throws -> (MemoraModel, MemoraTask, URL) {
    let url = root.appendingPathComponent(UUID().uuidString + ".sqlite")
    let model = try MemoraModel(storeURL: url)
    var privacy = RecordPrivacy(classification: .personal); privacy.allowsCloudAI = true
    let task = MemoraTask(id: UUID(), title: "架空の見積もり確認", assignee: "架空の担当", dueDate: Date(timeIntervalSince1970: 1_800_000_000),
      isCompleted: false, detail: "期限・担当・本文を保持", privacy: privacy)
    model.tasks = [task]
    precondition(model.persistNow(model.tasks, forKey: MemoraModel.StorageKey.tasks))
    model.message.interfaceTaskIDs = [task.id]
    let tool = AgentTool.updateTasks
    _ = model.fixtureRegistry.register(AIToolDefinition(id: "memora:" + tool.rawValue, name: tool.rawValue, summary: tool.summary,
      inputSchema: try JSONSerialization.data(withJSONObject: tool.inputSchema), provider: .memora, requiredPermissions: ["memora.write"],
      risk: .write, isAvailable: true, isEnabled: true))
    model.agentPluginPolicies[model.message.id] = AIPluginExecutionPolicy(pluginIDs: ["skill:fixture"], toolIDs: ["memora:update_tasks"],
      recordIDs: [], limitsRecordReads: false)
    if cloud {
      model.message.cloudProvenance = model.newCloudProvenance(references: [])
      model.message.cloudAuthorizationTargets = []
    }
    TaskReminderScheduler.refreshed = []
    return (model, task, url)
  }

  static func approvedFlow(root: URL, cloud: Bool) async throws {
    let (model, original, url) = try fixture(root: root, cloud: cloud)
    let messageID = model.message.id
    if cloud { model.recordCloudReads([.task(original.id)], messageID: messageID) }
    model.completeInterfaceTask(original.id, messageID: messageID)
    let operation = model.aiChatTask!
    model.completeInterfaceTask(original.id, messageID: messageID)
    let approval = await awaitingApproval(model)
    precondition(model.interfaceCalls.count == 1 && model.tasks == [original])
    try assertStored(url, equals: [original])
    precondition(!model.agentApprovalWaiter.resolve(true, id: UUID()), "A foreign card approved this action")
    precondition(model.agentApprovalWaiter.resolve(true, id: approval.id))
    precondition(!model.agentApprovalWaiter.resolve(true, id: approval.id), "Approval replay accepted")
    await operation.value
    let saved = model.tasks[0]
    var expected = original; expected.isCompleted = true; expected.completedAt = saved.completedAt
    precondition(saved == expected && saved.completedAt != nil)
    try assertStored(url, equals: [saved])
    precondition(TaskReminderScheduler.refreshed == [original.id])
    precondition(!model.isAIChatResponding && model.aiChatTask == nil && model.aiChatRequestID == nil)
    precondition(model.pendingAgentApproval == nil && model.message.agentSteps.last?.state == .done)
    if cloud {
      precondition(!model.canUseInterfaceContext(messageID: messageID), "A changed task silently refreshed its old cloud grant")
    }
    model.completeInterfaceTask(original.id, messageID: messageID)
    precondition(model.interfaceCalls.count == 1, "An already-completed task ran again")
  }

  static func declinedAndCancelled(root: URL, cloud: Bool) async throws {
    for mode in 0..<3 {
      let (model, task, url) = try fixture(root: root, cloud: cloud)
      model.completeInterfaceTask(task.id, messageID: model.message.id)
      let operation = model.aiChatTask!
      let approval = await awaitingApproval(model)
      if mode == 0 { model.agentApprovalWaiter.resolve(false, id: approval.id) }
      else {
        if mode == 2 { model.agentApprovalWaiter.resolve(true, id: approval.id) }
        operation.cancel()
      }
      await operation.value
      precondition(model.tasks == [task])
      try assertStored(url, equals: [task])
      precondition(TaskReminderScheduler.refreshed.isEmpty && model.pendingAgentApproval == nil)
      precondition(model.message.agentSteps.last?.state == .declined && !model.isAIChatResponding)
    }
  }

  static func rejectsBeforeDispatch(root: URL) async throws {
    for mode in 0..<5 {
      let (model, task, url) = try fixture(root: root)
      let messageID = model.message.id
      model.completeInterfaceTask(UUID(), messageID: messageID)
      model.completeInterfaceTask(task.id, messageID: UUID())
      precondition(model.aiChatTask == nil)
      model.completeInterfaceTask(task.id, messageID: messageID)
      let operation = model.aiChatTask!
      // The Task has been enqueued but has not entered the dispatcher yet.
      switch mode {
      case 0: model.message.interfaceTaskIDs = []
      case 1: model.currentTeamID = "team"
      case 2: model.isRestoring = true
      case 3: model.isStoreProtected = true
      default: model.hasMessage = false
      }
      await operation.value
      precondition(model.interfaceCalls.isEmpty && model.pendingAgentApproval == nil)
      precondition(model.tasks == [task])
      try assertStored(url, equals: [task])
    }
  }

  static func rechecksAfterApproval(root: URL) async throws {
    for mode in 0..<13 {
      let (model, task, url) = try fixture(root: root, cloud: true)
      model.completeInterfaceTask(task.id, messageID: model.message.id)
      let operation = model.aiChatTask!
      let approval = await awaitingApproval(model)
      switch mode {
      case 0: model.pluginPermitted = false
      case 1: model.fixtureRegistry.tools["memora:update_tasks"]?.isEnabled = false
      case 2: model.agentPluginPolicies.removeValue(forKey: model.message.id)
      case 3: model.agentPluginPolicies[model.message.id]?.toolIDs = []
      case 4: model.agentPluginPolicies[model.message.id]?.limitsRecordReads = true
      case 5: model.tasks[0].title = "ユーザーが編集中に変更"
      case 6: model.tasks = []
      case 7: model.currentTeamID = "other"
      case 8: model.isRestoring = true
      case 9: model.isStoreProtected = true
      case 10: model.rejectWrites = true
      case 11: model.hasMessage = false
      default: model.tasks[0].privacy?.allowsCloudAI = false
      }
      let unchanged = model.tasks
      model.agentApprovalWaiter.resolve(true, id: approval.id)
      await operation.value
      precondition(model.tasks == unchanged, "Stale approval wrote case \(mode)")
      try assertStored(url, equals: [task])
      precondition(TaskReminderScheduler.refreshed.isEmpty && model.pendingAgentApproval == nil)
      precondition(!model.isAIChatResponding && model.aiChatTask == nil)
    }
    // A private parent changed without changing the task value or cloud source list.
    let (model, task, url) = try fixture(root: root, cloud: true)
    var privacy = RecordPrivacy(classification: .personal); privacy.allowsCloudAI = true
    let meeting = Meeting(title: "架空の親会議", participantIDs: nil, privacy: privacy)
    model.meetings = [meeting]; model.tasks[0].meetingID = meeting.id
    let original = model.tasks[0]
    precondition(model.persistNow(model.tasks, forKey: MemoraModel.StorageKey.tasks))
    model.completeInterfaceTask(task.id, messageID: model.message.id)
    let operation = model.aiChatTask!
    let approval = await awaitingApproval(model)
    model.meetings[0].privacy.allowsCloudAI = false
    model.agentApprovalWaiter.resolve(true, id: approval.id)
    await operation.value
    precondition(model.tasks == [original])
    try assertStored(url, equals: [original])
  }

  static func validatesWholeBatch(root: URL) async throws {
    let (model, first, url) = try fixture(root: root)
    let second = MemoraTask(id: UUID(), title: "架空の別作業", isCompleted: false)
    model.tasks.append(second)
    precondition(model.persistNow(model.tasks, forKey: MemoraModel.StorageKey.tasks))
    for updates: [[String: Any]] in [
      [["id": first.id.uuidString, "is_completed": true], ["id": UUID().uuidString, "is_completed": true]],
      [["id": first.id.uuidString, "is_completed": true], ["id": first.id.uuidString, "is_completed": true]],
      [["id": first.id.uuidString, "is_completed": "true"]],
      [["id": first.id.uuidString, "arbitrary_code": "ignored?"], ["id": second.id.uuidString, "is_completed": true]]
    ] {
      let call = AgentToolCall(id: UUID().uuidString, name: "update_tasks", arguments: ["updates": updates])
      let operation = Task { await model.updateTasksTool(call, messageID: model.message.id, scope: .all) }
      let timeout = Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        if !Task.isCancelled { operation.cancel() }
      }
      let result = await operation.value
      timeout.cancel()
      precondition(result.isError && model.pendingAgentApproval == nil)
      precondition(model.tasks == [first, second])
      try assertStored(url, equals: [first, second])
    }
    let call = AgentToolCall(id: UUID().uuidString, name: "update_tasks", arguments: ["updates": [
      ["id": first.id.uuidString, "is_completed": true], ["id": second.id.uuidString, "is_completed": true]]])
    let operation = Task { await model.updateTasksTool(call, messageID: model.message.id, scope: .all) }
    let approval = await awaitingApproval(model)
    try failTaskWrites(url)
    model.agentApprovalWaiter.resolve(true, id: approval.id)
    let result = await operation.value
    precondition(result.isError && model.tasks == [first, second])
    try assertStored(url, equals: [first, second])
    precondition(model.message.agentSteps.last?.state == .failed && TaskReminderScheduler.refreshed.isEmpty)
    try executeSQL("DROP TRIGGER fail_task_write;", at: url)
    var retryCall = call; retryCall.id = UUID().uuidString
    let retry = Task { await model.updateTasksTool(retryCall, messageID: model.message.id, scope: .all) }
    let retryApproval = await awaitingApproval(model)
    model.agentApprovalWaiter.resolve(true, id: retryApproval.id)
    let retryResult = await retry.value
    precondition(!retryResult.isError && model.tasks.allSatisfy(\.isCompleted))
    try assertStored(url, equals: model.tasks)
    precondition(TaskReminderScheduler.refreshed == [first.id, second.id])
  }

  static func rechecksProjectMembership(root: URL) async throws {
    let (model, task, url) = try fixture(root: root)
    var meeting = Meeting(title: "架空の案件会議", participantIDs: nil, privacy: RecordPrivacy())
    meeting.spaceID = UUID()
    model.meetings = [meeting]; model.tasks[0].meetingID = meeting.id
    let original = model.tasks[0]
    precondition(model.persistNow(model.tasks, forKey: MemoraModel.StorageKey.tasks))
    let call = AgentToolCall(id: UUID().uuidString, name: "update_tasks", arguments: ["updates": [["id": task.id.uuidString, "is_completed": true]]])
    let operation = Task { await model.updateTasksTool(call, messageID: model.message.id, scope: .projects) }
    let approval = await awaitingApproval(model)
    model.meetings[0].spaceID = nil
    model.agentApprovalWaiter.resolve(true, id: approval.id)
    let result = await operation.value
    precondition(result.isError && model.tasks == [original])
    try assertStored(url, equals: [original])
  }

  static func failTaskWrites(_ url: URL) throws {
    try executeSQL("CREATE TRIGGER fail_task_write BEFORE INSERT ON documents WHEN NEW.key = 'tasks' BEGIN SELECT RAISE(ABORT, 'fixture save failure'); END;", at: url)
  }

  static func executeSQL(_ sql: String, at url: URL) throws {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw LocalStore.StoreError.open(0) }
    defer { sqlite3_close(connection) }
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw LocalStore.StoreError.statement(0) }
  }

  static func awaitingApproval(_ model: MemoraModel) async -> AgentApproval {
    for _ in 0..<10_000 {
      if let approval = model.pendingAgentApproval { return approval }
      await Task.yield()
    }
    preconditionFailure("Approval was never presented")
  }

  static func stored(_ url: URL) throws -> [MemoraTask] {
    let reopened = LocalStore(fileURL: url)
    try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome(MemoraModel.StorageKey.tasks) else { preconditionFailure("Missing saved tasks") }
    return try JSONDecoder().decode([MemoraTask].self, from: data)
  }

  static func assertStored(_ url: URL, equals expected: [MemoraTask]) throws {
    let actual = try stored(url)
    precondition(actual == expected, "SQLite tasks differ")
  }
}
