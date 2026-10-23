import Foundation

@main
struct GmailAgentChecks {
  @MainActor static func setup(compact: Bool, search: Bool = true) -> (MemoraModel, GmailServiceFixture, GmailService, AgentToolCall) {
    let model = MemoraModel()
    if compact { model.message.cloudProvenance = nil }
    let fixture = GmailServiceFixture()
    fixture.email = "connected@example.invalid"
    let service = GmailService(environment: fixture.environment)
    let call = AgentToolCall(id: "fixture", name: search ? "search_email" : "read_email",
      arguments: search ? ["query": "fixture", "limit": 2] : ["id": "message1"])
    return (model, fixture, service, call)
  }

  @MainActor static func mutate(_ mode: Int, model: MemoraModel, service: GmailService) async {
    switch mode {
    case 0: model.currentTeamID = "another-workspace"
    case 1: model.aiWorkspaceGeneration = UUID()
    case 2: model.aiChatRequestID = UUID()
    case 3: model.hasMessage = false
    case 4: model.message.isThinking = false
    case 5: model.isRestoring = true
    case 6: model.isStoreProtected = true
    case 7: model.agentPluginPolicies[model.message.id] = .init(pluginIDs: [], toolIDs: [], recordIDs: [], limitsRecordReads: true)
    case 8: model.pluginAvailable = false
    case 9: model.setIntegrationEnabled("gmail", enabled: false)
    case 10:
      model.setIntegrationEnabled("gmail", enabled: false)
      model.setIntegrationEnabled("gmail", enabled: true)
    case 11: await service.disconnect()
    case 12: try! await service.connect() // Same displayed email, different connection generation.
    default: model.cloudAuthorized = false
    }
  }

  @MainActor static func main() async throws {
    for compact in [false, true] {
      try await normalAndFailure(compact: compact)
      // Approval, token refresh, list response, first metadata response, full read.
      for phase in 0..<5 {
        for mode in 0..<(compact ? 13 : 14) { await suspended(compact: compact, phase: phase, mode: mode) }
      }
      await retained(compact: compact)
      await rejectedAuthorization(compact: compact)
      await loop(compact: compact)
      await cancelled(compact: compact)
    }
    let entry = try String(contentsOfFile: "App/MemoraModel+Agent.swift", encoding: .utf8)
    precondition(entry.components(separatedBy: "gmailResultsAreCurrent(messageID)").count >= 4)
    let dispatch = try String(contentsOfFile: "App/MemoraModel+AgentTools.swift", encoding: .utf8)
    precondition(dispatch.contains("return await gmailReadTool(call") && dispatch.contains("guard !automaticAccess else"))
    print("GmailAgentChecks: passed (production context/approval/read orchestration/Gmail service/registry/loop; 135 approval-refresh-list-metadata-full-read races, retained grants, cloud and compact, cancel/deny/errors; conversation/registry assembly/approval/browser/storage/HTTP are fixtures, no network/accounts)")
  }

  @MainActor static func normalAndFailure(compact: Bool) async throws {
    for search in [false, true] {
      let (model, fixture, service, call) = setup(compact: compact, search: search)
      let outcome = await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service)
      precondition(!outcome.isError && outcome.text.contains(search ? "Fixture subject" : "本文のfixture"))
      precondition(model.approvals == 1 && model.message.steps.last?.state == .done)
      precondition(model.message.gmailResultAuthorizationIDs.count == 1 && model.gmailResultsAreCurrent(model.message.id))
      if !compact { precondition(model.message.cloudProvenance?.isComplete == false) }
      precondition(fixture.requests.filter { $0.url?.host == "gmail.googleapis.com" }.allSatisfy { $0.httpMethod == "GET" })
    }
    let (denied, fixture, service, call) = setup(compact: compact)
    denied.approves = false
    let result = await denied.gmailReadTool(call, messageID: denied.message.id, compact: compact, service: service)
    precondition(!result.text.contains("Fixture subject") && fixture.requests.isEmpty)
    let repeated = await denied.gmailReadTool(call, messageID: denied.message.id, compact: compact, service: service)
    precondition(repeated.isError && denied.approvals == 1)
    precondition(denied.agentBlockedExternalTools[denied.message.id] == ["read_email", "search_email"])

    for status in [401, 403, 429, 500] {
      let (model, fixture, service, call) = setup(compact: compact)
      fixture.transportOverride = { request in
        fixture.response(request, status: request.url!.host == "gmail.googleapis.com" ? status : 200,
          json: request.url!.host == "gmail.googleapis.com" ? ["error": "PRIVATE_REMOTE_ERROR"] : nil)
      }
      let outcome = await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service)
      precondition(outcome.isError && !outcome.text.contains("PRIVATE_REMOTE_ERROR"))
      precondition(model.message.steps.last?.state == .failed && model.gmailResultAuthorizations.isEmpty)
    }
  }

  @MainActor static func suspended(compact: Bool, phase: Int, mode: Int) async {
    let (model, fixture, service, call) = setup(compact: compact, search: phase != 4)
    let gate = HTTPResponseGate()
    if phase == 0 { model.onApproval = { await gate.pause() } }
    var paused = false
    fixture.transportOverride = { request in
      let path = request.url!.path
      if !paused && ((phase == 1 && path == "/token") ||
          (phase == 2 && path == "/gmail/v1/users/me/messages") ||
          (phase >= 3 && path == "/gmail/v1/users/me/messages/message1")) {
        paused = true
        await gate.pause()
      }
      return fixture.response(request)
    }
    let operation = Task { await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service) }
    await gate.waitForRequest()
    await mutate(mode, model: model, service: service)
    let steps = model.message.steps
    let blocked = model.agentBlockedExternalTools
    await gate.release()
    let outcome = await operation.value
    precondition(outcome.isError && !outcome.text.contains("Fixture subject") && !outcome.text.contains("本文のfixture"))
    precondition(model.message.gmailResultAuthorizationIDs.isEmpty)
    let reads = fixture.requests.filter { $0.url!.path.hasPrefix("/gmail/v1/users/me/messages") }.count
    precondition(reads == (phase <= 1 ? 0 : phase == 3 ? 2 : 1))
    if mode <= 4 { precondition(model.message.steps == steps && model.agentBlockedExternalTools == blocked) }
    precondition(!model.message.steps.contains { $0.detail?.contains("Fixture subject") == true || !$0.results.isEmpty })
  }

  @MainActor static func retained(compact: Bool) async {
    for mode in 0..<(compact ? 15 : 16) {
      let (model, fixture, service, call) = setup(compact: compact)
      let first = await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service)
      precondition(!first.isError)
      let missing = compact ? 13 : 14
      if mode == missing { model.gmailResultAuthorizations.removeAll() }
      else if mode == missing + 1 { model.message.gmailResultAuthorizationIDs.insert(UUID()) }
      else { await mutate(mode, model: model, service: service) }
      let allowed = compact ? model.gmailResultsAreCurrent(model.message.id) : model.isCloudSessionAuthorized(model.message.id)
      precondition(!allowed)
      let reads = fixture.requests.count
      let again = await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service)
      precondition(again.isError && fixture.requests.count == reads)
    }
    let (model, _, service, call) = setup(compact: compact)
    for _ in 0..<24 {
      let result = await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service)
      precondition(!result.isError)
    }
    let overflow = await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service)
    precondition(overflow.isError && model.gmailResultAuthorizations.count == 24)
  }

  @MainActor static func loop(compact: Bool) async {
    for duringModel in [false, true] {
      let (model, _, service, call) = setup(compact: compact)
      let gate = HTTPResponseGate()
      var requests = 0
      var accepted = 0
      let operation = Task {
        await AgentConversationLoop.run(isAuthorized: {
          compact ? model.gmailResultsAreCurrent(model.message.id) : model.isCloudSessionAuthorized(model.message.id)
        }, next: {
          requests += 1
          if requests == 1 {
            return AgentTurn(text: "", toolCalls: duringModel ? [call] : [call, .init(id: "later", name: "fixture_wait", arguments: [:])])
          }
          await gate.pause()
          return AgentTurn(text: "PRIVATE_FINAL", toolCalls: [])
        }, execute: { next in
          if next.id == call.id { return await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service) }
          await gate.pause(); return AgentToolOutcome(text: "fixture")
        }, accept: { _, _ in accepted += 1 })
      }
      await gate.waitForRequest()
      model.setIntegrationEnabled("gmail", enabled: false)
      await gate.release()
      let result = await operation.value
      precondition(result.failure == .contextChanged && result.text == nil)
      precondition(requests == (duringModel ? 2 : 1) && accepted == (duringModel ? 1 : 0))
    }
  }

  @MainActor static func rejectedAuthorization(compact: Bool) async {
    for status in [401, 403, 429, 500] {
      let (model, fixture, service, call) = setup(compact: compact)
      let result = await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service)
      precondition(!result.isError)
      let revision = service.connectionRevision
      fixture.transportOverride = { request in fixture.response(request, status: status, json: ["error": "PRIVATE_ERROR"]) }
      do { _ = try await service.read("message1"); preconditionFailure() } catch {}
      precondition(service.isConnected)
      precondition((service.connectionRevision != revision) == (status == 401 || status == 403))
      precondition(model.gmailResultsAreCurrent(model.message.id) == (status != 401 && status != 403))
    }
    // Profile metadata is optional during sign-in. Its rejection must not
    // strand connect()'s generation-bound isWorking cleanup.
    for status in [401, 403] {
      let (_, fixture, service, _) = setup(compact: compact)
      fixture.transportOverride = { request in
        fixture.response(request, status: request.url!.lastPathComponent == "profile" ? status : 200)
      }
      do { try await service.connect() } catch { preconditionFailure("Optional profile failed sign-in") }
      precondition(service.isConnected && !service.isWorking && service.connectedEmail == nil)
    }
  }

  @MainActor static func cancelled(compact: Bool) async {
    let (model, fixture, service, call) = setup(compact: compact)
    let gate = HTTPResponseGate()
    fixture.transportOverride = { request in await gate.pause(); return fixture.response(request) }
    let operation = Task { await model.gmailReadTool(call, messageID: model.message.id, compact: compact, service: service) }
    await gate.waitForRequest(); operation.cancel(); await gate.release()
    let outcome = await operation.value
    precondition(outcome.isError && fixture.requests.count == 1 && model.gmailResultAuthorizations.isEmpty)
  }
}
