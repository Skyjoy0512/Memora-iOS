import Foundation

@main @MainActor
struct CalendarInterfaceChecks {
  static let day = "2026-10-19"
  static let call = AgentToolCall(id: "calendar-fixture", name: "read_calendar", arguments: ["date": day])

  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memora-calendar-interface-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try await checkLifecycle(root)
    for cloud in [false, true] {
      let model = try fixture(root, cloud: cloud)
      let result = await read(model, cloud: cloud)
      precondition(!result.isError && CalendarService.reads == 1 && model.message.calendarReadSnapshot?.events.count == 2)
      precondition(!result.text.contains("private-event"), "EventKit identifiers escaped the local boundary")
      let snapshot = model.message.calendarReadSnapshot!
      precondition(snapshot.isValid && !model.message.didChangeData)
      let ids = snapshot.events.map(\.id)
      let events = model.interfaceCalendarEvents(ids.reversed(), messageID: model.message.id)!
      precondition(events.map(\.title) == ["終日の予定", "翌日までの予定"] && events[0].isAllDay)
      precondition(model.interfaceCalendarEvents([UUID()], messageID: model.message.id) == nil)
      precondition(model.interfaceCalendarEvents(ids, messageID: UUID()) == nil)
      precondition(model.interfaceCalendarEvents([ids[0], ids[0]], messageID: model.message.id) == nil)
      _ = await read(model, cloud: cloud)
      precondition(model.message.calendarReadSnapshot?.events.map(\.id) == ids, "Occurrence IDs changed on repeated reads")
      for mutation in 0..<5 {
        switch mutation {
        case 0: model.currentTeamID = "other"
        case 1: model.isCalendarEnabled = false
        case 2: CalendarService.access = .denied
        case 3: model.isRestoring = true
        default: model.isStoreProtected = true
        }
        precondition(model.interfaceCalendarEvents(ids, messageID: model.message.id) == nil)
        if cloud { precondition(!model.isCloudSessionAuthorized(model.message.id)) }
        model.currentTeamID = nil; model.isCalendarEnabled = true; CalendarService.access = .granted
        model.isRestoring = false; model.isStoreProtected = false
      }
      model.invalidateAICalendarContext()
      precondition(model.interfaceCalendarEvents(ids, messageID: model.message.id) == nil)
      precondition(!model.artifactCreationIsCurrent(messageID: model.message.id, workspaceID: nil, provenance: model.artifactProvenance(for: model.message)))
      if cloud { precondition(!model.isCloudSessionAuthorized(model.message.id)) }
    }
    let denied = try fixture(root, cloud: true)
    let task = Task { await denied.readCalendarTool(call, messageID: denied.message.id) }
    let approval = await awaiting(denied)
    denied.agentApprovalWaiter.resolve(false, id: approval.id)
    _ = await task.value
    precondition(CalendarService.reads == 0 && denied.message.calendarReadSnapshot == nil)
    let retry = Task { await denied.readCalendarTool(call, messageID: denied.message.id) }
    let retryTimeout = Task {
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { retry.cancel() }
    }
    let retryResult = await retry.value
    retryTimeout.cancel()
    precondition(retryResult.isError && denied.pendingAgentApproval == nil && CalendarService.reads == 0)
    for mode in 0..<8 {
      let model = try fixture(root, cloud: false)
      CalendarService.onRead = {
        switch mode {
        case 0: model.currentTeamID = "other"
        case 1: CalendarService.access = .denied
        case 2: model.isCalendarEnabled = false
        case 3: model.calendarContextRevision = UUID()
        case 4: model.isRestoring = true
        case 5: model.hasMessage = false
        case 6: model.fixtureRegistry.tools["memora:read_calendar"]?.isEnabled = false
        default: withUnsafeCurrentTask { $0?.cancel() }
        }
      }
      let operation = Task { await model.readCalendarTool(call, messageID: model.message.id) }
      let result = await operation.value
      precondition(result.isError && model.message.calendarReadSnapshot == nil)
    }
    let changed = try fixture(root, cloud: true)
    let operation = Task { await changed.readCalendarTool(call, messageID: changed.message.id) }
    let changedApproval = await awaiting(changed)
    changed.agentPluginPolicies.removeValue(forKey: changed.message.id)
    changed.agentApprovalWaiter.resolve(true, id: changedApproval.id)
    let changedResult = await operation.value
    precondition(changedResult.isError && CalendarService.reads == 0)
    let empty = try fixture(root, cloud: false)
    CalendarService.values = []
    let emptyResult = await read(empty, cloud: false)
    precondition(!emptyResult.isError && empty.message.calendarReadSnapshot?.events.isEmpty == true)
    precondition(emptyResult.text.contains("予定はありません"))
    checkBounds()
    for cloud in [false, true] {
      let guarded = try fixture(root, cloud: cloud)
      let approval = AgentApproval(messageID: guarded.message.id, icon: .envelopeOpen, title: "Fixture write", lines: [], confirmTitle: "実行")
      guarded.gmailResultsCurrent = false
      let denied = await guarded.requestAgentApproval(approval)
      precondition(!denied && guarded.pendingAgentApproval == nil && !guarded.message.didChangeData)
      guarded.gmailResultsCurrent = true
      let operation = Task { await guarded.requestAgentApproval(approval) }
      let pending = await awaiting(guarded)
      guarded.gmailResultsCurrent = false
      guarded.agentApprovalWaiter.resolve(true, id: pending.id)
      let stale = await operation.value
      precondition(!stale && !guarded.message.didChangeData)
    }
    print("CalendarInterfaceChecks: passed (production read tool, approval/waiter, real schema/registry/policy, ephemeral UUID binding, actual-value rendering lookup, cloud pre-send authorization, invalidation/permissions/workspace, cancellation/deferred reads, stable recurrence IDs, empty/bounded sources; EventKit and registry assembly are mocks, no system calendar or network)")
  }

  static func fixture(_ root: URL, cloud: Bool) throws -> MemoraModel {
    let model = try MemoraModel(storeURL: root.appendingPathComponent(UUID().uuidString + ".sqlite"))
    model.aiChatRequestID = UUID()
    model.message.isThinking = true
    CalendarService.access = .granted; CalendarService.reads = 0; CalendarService.onRead = nil
    CalendarService.observationStarts = 0
    let start = Date(timeIntervalSince1970: 1_792_353_600)
    CalendarService.values = [
      .init(id: "private-event-1@occurrence", title: "終日の予定", start: start, end: start.addingTimeInterval(86_400), isAllDay: true),
      .init(id: "private-event-2@occurrence", title: "翌日までの予定", start: start.addingTimeInterval(85_000), end: start.addingTimeInterval(90_000), isAllDay: false)
    ]
    let tool = AgentTool.readCalendar
    _ = model.fixtureRegistry.register(AIToolDefinition(id: "memora:read_calendar", name: tool.rawValue, summary: tool.summary,
      inputSchema: try JSONSerialization.data(withJSONObject: tool.inputSchema), provider: .memora, requiredPermissions: ["memora.read"], risk: .read, isAvailable: true, isEnabled: true))
    model.agentPluginPolicies[model.message.id] = AIPluginExecutionPolicy(pluginIDs: ["service:calendar"], toolIDs: ["memora:read_calendar"], recordIDs: [], limitsRecordReads: true)
    if cloud {
      model.message.cloudProvenance = model.newCloudProvenance(references: [])
      model.message.cloudAuthorizationTargets = []
    }
    return model
  }

  static func read(_ model: MemoraModel, cloud: Bool) async -> AgentToolOutcome {
    let readsBeforeApproval = CalendarService.reads
    let operation = Task { await model.readCalendarTool(call, messageID: model.message.id) }
    if cloud {
      let approval = await awaiting(model)
      precondition(CalendarService.reads == readsBeforeApproval, "Calendar read started before approval")
      precondition(CalendarService.observationStarts > 0, "Calendar changes were not observed during approval")
      model.agentApprovalWaiter.resolve(true, id: approval.id)
    }
    return await operation.value
  }

  static func awaiting(_ model: MemoraModel) async -> AgentApproval {
    for _ in 0..<10_000 {
      if let approval = model.pendingAgentApproval { return approval }
      await Task.yield()
    }
    preconditionFailure("Calendar approval missing")
  }

  static func checkBounds() {
    let revision = UUID(), date = Date.now
    var snapshot = AICalendarReadSnapshot(revision: revision, readAt: date, events: [])
    for batch in 0..<5 {
      let events = (0..<31).map { i in AICalendarEventReference(sourceID: "\(batch)-\(i)", title: "架空", start: date, end: date, isAllDay: false) }
      snapshot = snapshot.merging(events, at: date)
    }
    precondition(snapshot.isValid && snapshot.events.count == 120)
    var invalid = snapshot; invalid.events[1].id = invalid.events[0].id
    precondition(!invalid.isValid)
    invalid = snapshot; invalid.events[0].end = date.addingTimeInterval(-1)
    precondition(!invalid.isValid)
    let id = UUID().uuidString
    let valid = "{\"version\":1,\"components\":[{\"id\":\"agenda\",\"kind\":\"CalendarPreview\",\"items\":[{\"id\":\"event\",\"referenceID\":\"\(id)\"}]}]}"
    precondition(NativeAIInterface.decode(valid) != nil)
    var stream = NativeAIComponentStream()
    precondition(stream.update(String(valid.dropLast(2)))?.components.first?.kind == .calendarPreview)
    for addition in [",\"title\":\"fake event\"", ",\"detail\":\"fake time\"", ",\"action\":\"completeTask\"", ",\"value\":50"] {
      precondition(NativeAIInterface.decode(valid.replacingOccurrences(of: "\"referenceID\":\"\(id)\"", with: "\"referenceID\":\"\(id)\"" + addition)) == nil)
    }
  }

  static func checkLifecycle(_ root: URL) async throws {
    let changes: [(String, (MemoraModel) -> Void)] = [
      ("new request", { $0.aiChatRequestID = UUID() }),
      ("stopped request", { $0.aiChatRequestID = nil }),
      ("workspace ABA", { $0.currentTeamID = "other"; $0.aiWorkspaceGeneration = UUID(); $0.currentTeamID = nil }),
      ("replaced message", { $0.message.id = UUID() }),
      ("settled message", { $0.message.isThinking = false }),
      ("missing message", { $0.hasMessage = false }),
      ("restoring", { $0.isRestoring = true }),
      ("protected store", { $0.isStoreProtected = true }),
      ("calendar changed", { $0.invalidateAICalendarContext() }),
      ("integration disabled", { $0.setIntegrationEnabled("calendar", enabled: false) }),
      ("integration ABA", { $0.setIntegrationEnabled("calendar", enabled: false); $0.setIntegrationEnabled("calendar", enabled: true) }),
      ("permission denied", { _ in CalendarService.access = .denied }),
      ("permission unknown", { _ in CalendarService.access = .unknown }),
      ("policy removed", { $0.agentPluginPolicies.removeValue(forKey: $0.message.id) }),
      ("registry disabled", { $0.fixtureRegistry.tools["memora:read_calendar"]?.isEnabled = false }),
      ("plugin refused", { $0.pluginPermitted = false }),
      ("Gmail result revoked", { $0.gmailResultsCurrent = false }),
      ("MCP result revoked", { $0.mcpResultsCurrent = false })
    ]
    var checked = 0
    for cloud in [false, true] {
      for phase in cloud ? ["approval", "read"] : ["read"] {
        for (name, change) in changes {
          let model = try fixture(root, cloud: cloud)
          let originalID = model.message.id
          if phase == "read" { CalendarService.onRead = { change(model) } }
          let operation = Task { await model.readCalendarTool(call, messageID: originalID) }
          if cloud {
            let pending = await awaiting(model)
            if phase == "approval" { change(model) }
            model.agentApprovalWaiter.resolve(true, id: pending.id)
          }
          let result = await operation.value
          precondition(result.isError && model.message.calendarReadSnapshot == nil,
            "Stale calendar result accepted: \(cloud ? "cloud" : "device") / \(phase) / \(name)")
          precondition(!result.text.contains("終日の予定") && !result.text.contains("翌日までの予定"))
          precondition(CalendarService.reads == (phase == "approval" ? 0 : 1))
          precondition(!model.message.didChangeData)
          if ["new request", "stopped request", "workspace ABA", "replaced message", "settled message", "missing message"].contains(name) {
            precondition(model.message.agentSteps.allSatisfy { $0.state == .running }, "Old callback modified a settled/replacement trace")
            precondition(model.agentBlockedExternalTools[originalID, default: []].isEmpty, "Old callback modified a replacement's blocked tools")
          }
          checked += 1
        }
      }
    }
    print("Calendar lifecycle checks passed: \(checked) ownership/permission changes across approval and suspended reads, cloud and device")
    for cloud in [false, true] {
      let model = try fixture(root, cloud: cloud)
      let initial = await read(model, cloud: cloud)
      precondition(!initial.isError)
      let snapshot = model.message.calendarReadSnapshot!
      model.setIntegrationEnabled("calendar", enabled: true)
      precondition(model.calendarReadIsCurrent(snapshot), "An unchanged setting invalidated a valid read")
      model.setIntegrationEnabled("calendar", enabled: false)
      model.setIntegrationEnabled("calendar", enabled: true)
      precondition(!model.calendarReadIsCurrent(snapshot))
      precondition(model.interfaceCalendarEvents(snapshot.events.map(\.id), messageID: model.message.id) == nil)
      precondition(!model.artifactCreationIsCurrent(messageID: model.message.id, workspaceID: nil,
        provenance: model.artifactProvenance(for: model.message)))
      if cloud { precondition(!model.isCloudSessionAuthorized(model.message.id)) }
      let previousPolicy = model.agentPluginPolicies[model.message.id]
      model.message = FixtureMessage()
      model.message.isThinking = true
      model.aiChatRequestID = UUID()
      model.agentPluginPolicies[model.message.id] = previousPolicy
      if cloud {
        model.message.cloudProvenance = model.newCloudProvenance(references: [])
        model.message.cloudAuthorizationTargets = []
      }
      let fresh = await read(model, cloud: cloud)
      precondition(!fresh.isError && CalendarService.reads == 2)
      precondition(model.message.calendarReadSnapshot?.revision == model.calendarContextRevision)
      precondition(model.message.calendarReadSnapshot?.events.map(\.id) != snapshot.events.map(\.id))
    }
    print("Calendar lifecycle recovery passed: no-op setting retains grant; OFF/ON revokes preview/cloud/artifact use; a new approved request recovers with fresh IDs")
  }
}
