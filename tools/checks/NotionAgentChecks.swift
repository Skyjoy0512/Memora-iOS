import Foundation

@main
struct NotionAgentChecks {
  static let pageID = "44517d92-2356-498d-a923-d79d520667e0"
  static let pageURL = "https://www.notion.so/44517d922356498da923d79d520667e0"

  @MainActor static func setup(compact: Bool = false) -> (MemoraModel, NotionAgentWire, AgentToolCall) {
    KeychainStore.value = "fixture-token"; KeychainStore.fails = false
    let model = MemoraModel()
    if compact { model.message.cloudProvenance = nil }
    let meeting = Meeting()
    model.meetings = [meeting]
    var allowed = RecordPrivacy(classification: .personal); allowed.allowsCloudAI = true
    model.tasks = [
      MemoraTask(id: UUID(), title: "ALLOWED_FIXTURE_TASK", meetingID: meeting.id, isCompleted: false, privacy: allowed),
      MemoraTask(id: UUID(), title: "DENIED_FIXTURE_TASK", meetingID: meeting.id, isCompleted: false, privacy: .init(classification: .personal)),
      MemoraTask(id: UUID(), title: "OTHER_FIXTURE_TASK", meetingID: UUID(), isCompleted: false, privacy: allowed)
    ]
    return (model, NotionAgentWire(), .init(id: "fixture-call", name: "save_to_notion", arguments: ["meeting_id": meeting.id.uuidString]))
  }

  @MainActor static func mutate(_ mode: Int, model: MemoraModel, wire: NotionAgentWire) {
    switch mode {
    case 0: model.currentTeamID = "another-workspace"
    case 1: model.aiWorkspaceGeneration = UUID()
    case 2: model.aiChatRequestID = UUID()
    case 3: model.hasMessage = false
    case 4: model.message.isThinking = false
    case 5: model.isRestoring = true
    case 6: model.isStoreProtected = true
    case 7: model.meetings[0].privacy.allowsCloudAI = false
    case 8: model.meetings[0].title = "Changed record"
    case 9: model.meetings.removeAll()
    case 10: model.tasks[0].privacy?.allowsCloudAI = false
    case 11: model.tasks[0].title = "Changed task"
    case 12: model.tasks.removeFirst()
    case 13: model.setIntegrationEnabled("notion", enabled: false)
    case 14:
      model.setIntegrationEnabled("notion", enabled: false)
      model.setIntegrationEnabled("notion", enabled: true)
    case 15: model.agentPluginPolicies[model.message.id] = .init(pluginIDs: [], toolIDs: [], recordIDs: [], limitsRecordReads: true)
    case 16: model.pluginAvailable = false
    case 17: model.cloudAuthorized = false
    case 18: model.gmailAuthorized = false
    case 19: precondition(NotionService.storeToken("changed-fixture"))
    case 20: wire.changeParent("another-parent")
    case 21:
      precondition(NotionService.storeToken("changed-fixture"))
      precondition(NotionService.storeToken("fixture-token"))
    case 22:
      wire.changeParent("another-parent"); wire.changeParent("fixture-parent")
    default: precondition(NotionService.storeToken(nil))
    }
  }

  @MainActor static func main() async throws {
    try await normalAndRefusal()
    for compact in [false, true] {
      for phase in 0..<4 {
        for mode in 0..<24 where !compact || mode != 17 {
          await suspended(compact: compact, phase: phase, mode: mode)
        }
      }
    }
    for phase in 1...3 {
      for mode in [0, 1, 5, 6, 7, 8, 9, 10, 11, 12, 19, 20, 21, 22, 23] {
        await manualSuspended(phase: phase, mode: mode)
      }
    }
    await cancellationsAndFailures()
    try settingsEpochs()
    let detail = try String(contentsOfFile: "App/MeetingDetailView.swift", encoding: .utf8)
    precondition(detail.contains("model.saveMeetingToNotion(meeting.id, environment: .live)"))
    precondition(!detail.contains("NotionService.save(meeting:"))
    let settings = try String(contentsOfFile: "App/NotionSettingsView.swift", encoding: .utf8)
    precondition(settings.contains("guard NotionService.storeToken(token) else") && settings.contains("NotionService.configurationDidChange()"))
    print("NotionAgentChecks: passed (production service/export/agent/context/settings epoch + registry/privacy policies; 188 suspended agent and 45 manual races, partial identity, deny/cancel/HTTP errors, exact permitted tasks, manual export remains available with Ask AI disabled; model/record shape/registry assembly/approval/Keychain/HTTP are fixtures, no network/accounts)")
  }

  @MainActor static func normalAndRefusal() async throws {
    for manual in [false, true] {
      let (model, wire, call) = setup()
      if manual {
        let result = try await model.saveMeetingToNotion(model.meetings[0].id, environment: wire.environment)
        precondition(result.isComplete && result.pageURL?.absoluteString == pageURL && model.approvals == 0)
      } else {
        let result = await model.saveToNotionTool(call, messageID: model.message.id, scope: .all, environment: wire.environment)
        precondition(!result.isError && result.text.contains(pageURL) && model.approvals == 1 && result.dataChange == .committed)
        precondition(Set(model.recordedReads) == [.meeting(model.meetings[0].id), .task(model.tasks[0].id)])
      }
      precondition(wire.requests.count == 3)
      let bodies = wire.requests.map { String(decoding: $0.httpBody!, as: UTF8.self) }.joined()
      precondition(bodies.contains("ALLOWED_FIXTURE_TASK") && !bodies.contains("DENIED_FIXTURE_TASK") && !bodies.contains("OTHER_FIXTURE_TASK"))
    }
    let (denied, wire, call) = setup()
    denied.approves = false
    let result = await denied.saveToNotionTool(call, messageID: denied.message.id, scope: .all, environment: wire.environment)
    precondition(!result.text.contains(pageURL) && wire.requests.isEmpty && denied.message.steps.last?.state == .declined && result.dataChange == .none)
    let repeated = await denied.saveToNotionTool(call, messageID: denied.message.id, scope: .all, environment: wire.environment)
    precondition(repeated.isError && denied.approvals == 1)
    for mode in [0, 5, 6, 7, 9] {
      let (model, wire, _) = setup()
      let id = model.meetings[0].id
      mutate(mode, model: model, wire: wire)
      do { _ = try await model.saveMeetingToNotion(id, environment: wire.environment); preconditionFailure() } catch {}
      precondition(wire.requests.isEmpty)
    }
    let (manual, manualWire, _) = setup()
    manual.setIntegrationEnabled("notion", enabled: false)
    let manualResult = try await manual.saveMeetingToNotion(manual.meetings[0].id, environment: manualWire.environment)
    precondition(manualResult.isComplete && manual.approvals == 0)
    // Newly added tasks are not silently added to an already approved payload.
    let (model, newWire, newCall) = setup()
    model.onApproval = { model.tasks.append(.init(id: UUID(), title: "AFTER_APPROVAL", meetingID: model.meetings[0].id, isCompleted: false)) }
    let accepted = await model.saveToNotionTool(newCall, messageID: model.message.id, scope: .all, environment: newWire.environment)
    precondition(!accepted.isError && !newWire.requests.contains { String(decoding: $0.httpBody!, as: UTF8.self).contains("AFTER_APPROVAL") })
  }

  @MainActor static func suspended(compact: Bool, phase: Int, mode: Int) async {
    let (model, wire, call) = setup(compact: compact)
    let gate = HTTPResponseGate()
    if phase == 0 { model.onApproval = { await gate.pause() } }
    else { wire.pauseAt = phase; wire.gate = gate }
    let operation = Task { await model.saveToNotionTool(call, messageID: model.message.id, scope: .all, environment: wire.environment) }
    await gate.waitForRequest()
    mutate(mode, model: model, wire: wire)
    let steps = model.message.steps
    await gate.release()
    let result = await operation.value
    precondition(result.isError && !result.text.contains(pageURL))
    precondition(wire.requests.count == phase)
    precondition(result.dataChange == (phase == 0 ? .none : .committed))
    if mode <= 4 { precondition(model.message.steps == steps) }
    else if phase > 0 { precondition(model.message.steps.last?.detail?.contains(pageURL) == true) }
  }

  @MainActor static func manualSuspended(phase: Int, mode: Int) async {
    let (model, wire, _) = setup()
    let gate = HTTPResponseGate(); wire.pauseAt = phase; wire.gate = gate
    let operation = Task { () -> Error? in
      do { _ = try await model.saveMeetingToNotion(model.meetings[0].id, environment: wire.environment); return nil } catch { return error }
    }
    await gate.waitForRequest(); mutate(mode, model: model, wire: wire); await gate.release()
    guard let error = await operation.value, let partial = error as? NotionService.PartialPageFailure else { preconditionFailure("Lost partial page") }
    precondition(partial.pageID == pageID && partial.pageURL?.absoluteString == pageURL && wire.requests.count == phase)
  }

  @MainActor static func cancellationsAndFailures() async {
    for phase in 0..<4 {
      let (model, wire, call) = setup()
      let gate = HTTPResponseGate()
      if phase == 0 { model.onApproval = { await gate.pause() } }
      else { wire.pauseAt = phase; wire.gate = gate }
      let operation = Task { await model.saveToNotionTool(call, messageID: model.message.id, scope: .all, environment: wire.environment) }
      await gate.waitForRequest(); operation.cancel(); await gate.release()
      let result = await operation.value
      precondition(result.isError && !result.text.contains(pageURL) && wire.requests.count == phase)
    }
    for status in [401, 403, 429, 500] {
      for failAt in [1, 2, 3] {
        let (model, wire, call) = setup()
        wire.failAt = failAt; wire.status = status
        let result = await model.saveToNotionTool(call, messageID: model.message.id, scope: .all, environment: wire.environment)
        precondition(result.isError && wire.requests.count == failAt)
        precondition(result.dataChange == (failAt == 1 ? .unconfirmed : .committed))
        if failAt > 1 { precondition(result.text.contains(pageURL)) }
        let repeated = await model.saveToNotionTool(call, messageID: model.message.id, scope: .all, environment: wire.environment)
        precondition(repeated.isError && wire.requests.count == failAt && model.approvals == 1)
      }
    }
  }

  @MainActor static func settingsEpochs() throws {
    let (_, wire, _) = setup()
    let first = wire.environment.configuration()!
    precondition(NotionService.storeToken("other")); precondition(NotionService.storeToken("fixture-token"))
    let second = wire.environment.configuration()!
    precondition(first.token == second.token && first.parentPageID == second.parentPageID && first.revision != second.revision)
    wire.changeParent("other"); wire.changeParent("fixture-parent")
    precondition(wire.environment.configuration() != second)
    KeychainStore.fails = true
    precondition(!NotionService.storeToken("failed") && KeychainStore.value == "fixture-token")
    precondition(!NotionService.storeToken(nil) && KeychainStore.value == "fixture-token")
    KeychainStore.fails = false
  }
}

@MainActor final class NotionAgentWire {
  var parent = "fixture-parent"
  var requests: [URLRequest] = []
  var pauseAt = 0
  var gate: HTTPResponseGate?
  var failAt = 0
  var status = 500
  func changeParent(_ value: String) { NotionService.configurationDidChange(); parent = value }
  var environment: NotionSaveEnvironment {
    .init(configuration: { NotionService.readConfiguration(token: { KeychainStore.value }, parentPageID: { self.parent }) }, transport: { request in
      self.requests.append(request)
      if self.requests.count == self.pauseAt { await self.gate?.pause() }
      let status = self.requests.count == self.failAt ? self.status : 200
      return (Data("{\"id\":\"\(NotionAgentChecks.pageID)\",\"url\":\"\(NotionAgentChecks.pageURL)\"}".utf8),
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    })
  }
}
