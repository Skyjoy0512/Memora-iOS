import Foundation
import SQLite3

@main
struct MCPAgentChecks {
  @MainActor static func setup(_ root: URL, readOnly: Bool = false) throws -> (MemoraModel, MCPTool, AgentToolCall) {
    MCPClient.shared.reset()
    let model = try MemoraModel(root: root)
    let id = UUID()
    let tool = MCPTool(serverID: id, serverName: "Fixture", name: "read_fixture", summary: "Fixture tool",
      inputSchema: Data("{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}".utf8), isReadOnly: readOnly)
    var server = MCPServerConfig(id: id, name: tool.serverName, url: "https://fixture.example.invalid/mcp")
    server.reviewedEndpoint = server.url
    server.hasUsageCharges = false
    server.approvedReadToolFingerprints = [tool.name: tool.fingerprint]
    model.mcpServers = [server]
    model.activeMCPTools = [tool.agentName: tool]
    MCPClient.shared.offered[id] = [tool]
    return (model, tool, AgentToolCall(id: "fixture-call", name: tool.agentName, arguments: [:]))
  }

  @MainActor static func mutate(_ mode: Int, _ model: MemoraModel, _ tool: MCPTool) {
    switch mode {
    case 0: model.currentTeamID = "another-workspace"
    case 1: model.aiWorkspaceGeneration = UUID() // Includes personal -> team -> personal.
    case 2: model.aiChatRequestID = UUID()
    case 3: model.hasMessage = false
    case 4: model.message.isThinking = false
    case 5: model.isRestoring = true
    case 6: model.isStoreProtected = true
    case 7: model.cloudAuthorized = false // Existing record/memory/calendar provenance gate.
    case 8: model.agentPluginPolicies[model.message.id] = .init(pluginIDs: [], toolIDs: [], recordIDs: [], limitsRecordReads: true)
    case 9: model.setIntegrationEnabled("mcp", enabled: false)
    case 10: model.mcpServers.removeAll()
    case 11: model.mcpServers[0].isEnabled = false
    case 12: model.mcpServers[0].url = "https://changed.example.invalid/mcp"
    case 13: model.mcpServers[0].reviewedEndpoint = nil
    case 14: model.mcpServers[0].hasUsageCharges = true
    case 15: model.mcpCredentialRevisions[tool.serverID] = UUID()
    case 16: KeychainStore.values[model.mcpServers[0].tokenAccount] = "changed-fixture-token"
    case 17: model.mcpServers[0].approvedReadToolFingerprints = nil
    case 19:
      let active = model.activeMCPTools
      model.setIntegrationEnabled("mcp", enabled: false)
      model.setIntegrationEnabled("mcp", enabled: true)
      model.activeMCPTools = active
    case 20:
      let original = model.mcpServers[0]
      var disabled = original; disabled.isEnabled = false
      precondition(model.saveMCPServer(disabled, token: nil))
      precondition(model.saveMCPServer(original, token: nil))
    default: model.activeMCPTools[tool.agentName]?.summary = "changed fingerprint"
    }
  }

  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try await approvalAndBudgets(root)
    for phase in 0..<3 {
      for mode in 0..<21 { try await suspendedExecution(root, phase: phase, mode: mode) }
    }
    try await discovery(root)
    try await cancelled(root)
    // SDK-dependent code is compiled by Bitrig, not run in this host binary.
    let client = try String(contentsOfFile: "App/MCPClient.swift", encoding: .utf8)
    precondition(client.contains("generations[server.id] == generation"))
    precondition(client.components(separatedBy: "await isAuthorized()").count >= 8)
    let entry = try String(contentsOfFile: "App/MemoraModel+Agent.swift", encoding: .utf8)
    precondition(entry.contains("loadMCPToolsForAgent(messageID: placeholder.id"))
    print("MCPAgentChecks: passed (production discovery/execution/registry/provider/budgets with real SQLite, 63 suspended approval/preparation/result races, stale discovery ownership and final filtering, denial/error/cancel; model/provenance/approval/Keychain/SDK transport are fixtures, no network/accounts)")
  }

  @MainActor static func approvalAndBudgets(_ root: URL) async throws {
    for mode in 0..<5 {
      let (model, tool, call) = try setup(root, readOnly: mode != 0)
      switch mode {
      case 2: model.mcpServers[0].hasUsageCharges = nil
      case 3: model.message.cloudProvenance?.references = [UUID()]
      case 4: model.isAIMemoryEnabled = true; model.aiMemories = ["fixture"]
      default: break
      }
      let outcome = await model.performMCPTool(tool, call: call, messageID: model.message.id)
      precondition(!outcome.isError && outcome.text.contains("PRIVATE_FIXTURE_RESULT"))
      precondition(model.approvals == (mode == 1 ? 0 : 1) && MCPClient.shared.dispatched == 1)
      precondition(model.message.steps.last?.state == .done)
      let reopened = LocalStore(fileURL: model.storeURL)
      try reopened.prepare()
      guard case .data(let data) = reopened.readOutcome("memora.integrations.usage.v1") else { preconditionFailure() }
      let usage = try JSONDecoder().decode([IntegrationUsage].self, from: data)
      precondition(usage.first?.count == 1)
    }
    let (denied, tool, call) = try setup(root)
    denied.approves = false
    let refusal = await denied.performMCPTool(tool, call: call, messageID: denied.message.id)
    precondition(!refusal.text.contains("PRIVATE_FIXTURE_RESULT") && MCPClient.shared.dispatched == 0 && denied.integrationUsage.isEmpty)
    precondition(denied.message.steps.last?.state == .declined)

    for saveFailure in [false, true] {
      let (model, tool, call) = try setup(root)
      if saveFailure {
        var handle: OpaquePointer?
        precondition(sqlite3_open(model.storeURL.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        precondition(sqlite3_exec(handle, "CREATE TRIGGER reject_usage BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT,'fixture'); END;", nil, nil, nil) == SQLITE_OK)
      } else { model.integrationUsage = [.init(day: Calendar.current.startOfDay(for: .now), serverID: tool.serverID, count: 50)] }
      let outcome = await model.performMCPTool(tool, call: call, messageID: model.message.id)
      precondition(outcome.isError && MCPClient.shared.dispatched == 0)
      precondition(model.integrationUsage.count == (saveFailure ? 0 : 1))
    }
    for error in [MCPClientError.timeout as Error, ExternalToolFailure.authenticationExpired,
      ExternalToolFailure.permissionDenied, ExternalToolFailure.rateLimited, MCPClientError.server("PRIVATE_ERROR_PAYLOAD")] {
      let (model, tool, call) = try setup(root)
      MCPClient.shared.failure = error
      let outcome = await model.performMCPTool(tool, call: call, messageID: model.message.id)
      precondition(outcome.isError && !outcome.text.contains("PRIVATE_ERROR_PAYLOAD") && MCPClient.shared.dispatched == 1)
      precondition(model.message.steps.last?.state == .failed)
    }
    let (model, otherTool, otherCall) = try setup(root)
    model.agentPluginPolicies[model.message.id] = .init(pluginIDs: [], toolIDs: [], recordIDs: [], limitsRecordReads: true)
    let outcome = await model.performMCPTool(otherTool, call: otherCall, messageID: model.message.id)
    precondition(outcome.isError && model.approvals == 0 && MCPClient.shared.dispatched == 0)
  }

  @MainActor static func suspendedExecution(_ root: URL, phase: Int, mode: Int) async throws {
    let (model, tool, call) = try setup(root)
    let id = model.message.id
    let gate = HTTPResponseGate()
    if phase == 0 { model.onApproval = { await gate.pause() } }
    if phase == 1 { MCPClient.shared.beforeDispatch = { await gate.pause() } }
    if phase == 2 { MCPClient.shared.afterDispatch = { await gate.pause() } }
    let operation = Task { await model.performMCPTool(tool, call: call, messageID: id) }
    await gate.waitForRequest()
    mutate(mode, model, tool)
    let afterMutation = model.message.steps
    await gate.release()
    let outcome = await operation.value
    precondition(outcome.isError && !outcome.text.contains("PRIVATE_FIXTURE_RESULT"))
    precondition(MCPClient.shared.dispatched == (phase == 2 ? 1 : 0))
    if mode <= 4 { precondition(model.message.steps == afterMutation) }
    else { precondition(model.message.steps.last?.state == .failed) }
  }

  @MainActor static func discovery(_ root: URL) async throws {
    for mode in (0..<21).filter({ $0 != 18 }) {
      let (model, tool, _) = try setup(root)
      let gate = HTTPResponseGate()
      MCPClient.shared.beforeList = { _ in await gate.pause() }
      let operation = Task { await model.loadMCPToolsForAgent(messageID: model.message.id) }
      await gate.waitForRequest()
      mutate(mode, model, tool)
      let marker = MCPTool(serverID: UUID(), serverName: "New owner", name: "new", summary: "", inputSchema: Data(), isReadOnly: true)
      // A newer conversation can already own a different active registry.
      if mode <= 8 || mode == 19 { model.activeMCPTools = [marker.agentName: marker] }
      await gate.release()
      let result = await operation.value
      precondition(result.isEmpty)
      if mode <= 8 || mode == 19 { precondition(model.activeMCPTools[marker.agentName] == marker) }
    }
    let (model, first, _) = try setup(root)
    var second = model.mcpServers[0]
    second.id = UUID(); second.name = "Second"
    let tool = MCPTool(serverID: second.id, serverName: second.name, name: "second", summary: "", inputSchema: first.inputSchema, isReadOnly: true)
    model.mcpServers.append(second)
    MCPClient.shared.offered[second.id] = [tool]
    let gate = HTTPResponseGate()
    MCPClient.shared.beforeList = { id in if id == second.id { await gate.pause() } }
    let operation = Task { await model.loadMCPToolsForAgent(messageID: model.message.id) }
    await gate.waitForRequest()
    model.mcpServers[0].isEnabled = false
    await gate.release()
    let selected = await operation.value
    precondition(selected == [tool] && model.activeMCPTools[first.agentName] == nil)

    let (unknown, cached, _) = try setup(root)
    unknown.mcpServers[0].hasUsageCharges = nil
    let offered = await unknown.loadMCPToolsForAgent(messageID: unknown.message.id)
    precondition(offered == [cached] && MCPClient.shared.listCalls.isEmpty && MCPClient.shared.cacheReads.count == 1)
  }

  @MainActor static func cancelled(_ root: URL) async throws {
    for phase in 0..<3 {
      let (model, tool, call) = try setup(root)
      let gate = HTTPResponseGate()
      if phase == 0 { model.onApproval = { await gate.pause() } }
      if phase == 1 { MCPClient.shared.beforeDispatch = { await gate.pause() } }
      if phase == 2 { MCPClient.shared.afterDispatch = { await gate.pause() } }
      let operation = Task { await model.performMCPTool(tool, call: call, messageID: model.message.id) }
      await gate.waitForRequest()
      operation.cancel()
      await gate.release()
      let outcome = await operation.value
      precondition(!outcome.text.contains("PRIVATE_FIXTURE_RESULT") && MCPClient.shared.dispatched == (phase == 2 ? 1 : 0))
    }
  }
}
