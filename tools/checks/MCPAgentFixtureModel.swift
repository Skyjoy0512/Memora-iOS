import Foundation

// State/approval/provenance inputs are fixtures. The runner uses production MCP
// orchestration, provider, registry, policies, call budgets and SQLite storage.
@MainActor
final class MemoraModel {
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var aiChatRequestID: UUID? = UUID()
  var isRestoring = false
  var isStoreProtected = false
  var cloudAuthorized = true
  var message = MCPFixtureMessage()
  var hasMessage = true
  var mcpServers: [MCPServerConfig] = []
  var mcpCredentialRevisions: [UUID: UUID] = [:]
  var mcpPermissionRevision = UUID()
  var gmailPermissionRevision = UUID()
  var notionPermissionRevision = UUID()
  var mcpResultAuthorizations: [UUID: MCPResultAuthorization] = [:]
  var activeMCPTools: [String: MCPTool] = [:]
  var agentPluginPolicies: [UUID: AIPluginExecutionPolicy] = [:]
  var agentBlockedExternalTools: [UUID: Set<String>] = [:]
  var agentToolCallCounts: [UUID: Int] = [:]
  var disabledIntegrationIDs: [String] = []
  var disabledSkillIDs: [String] = []
  var integrationUsage: [IntegrationUsage] = []
  var isAIMemoryEnabled = false
  var aiMemories: [String] = []
  var approvals = 0
  var approves = true
  var onApproval: (() async -> Void)?

  func invalidateAICalendarContext() { preconditionFailure("Calendar is covered by CalendarInterfaceChecks") }
  let store: LocalStore
  let storeURL: URL

  init(root: URL) throws {
    storeURL = root.appendingPathComponent(UUID().uuidString + ".sqlite")
    store = LocalStore(fileURL: storeURL)
    try store.prepare()
  }

  func agentMessage(_ id: UUID) -> MCPFixtureMessage? { hasMessage && message.id == id ? message : nil }
  func isCloudSessionAuthorized(_ id: UUID) -> Bool { cloudAuthorized && mcpResultsAreCurrent(id) }
  func updateAgentMessage(_ id: UUID, _ update: (inout MCPFixtureMessage) -> Void) {
    guard hasMessage, message.id == id else { return }
    update(&message)
  }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do { try store.write(key, data: JSONEncoder().encode(value)); return true } catch { return false }
  }
  func beginAgentStep(_ step: AgentStep, on id: UUID) -> UUID {
    precondition(id == message.id)
    message.steps.append(step)
    return step.id
  }
  func finishAgentStep(_ id: UUID, on messageID: UUID, state: AgentStep.State, detail: String? = nil) {
    guard message.id == messageID, let index = message.steps.firstIndex(where: { $0.id == id }) else { return }
    message.steps[index].state = state
    message.steps[index].detail = detail
  }
  func requestAgentApproval(_ approval: AgentApproval) async -> Bool {
    approvals += 1
    await onApproval?()
    return approves
  }
}

struct MCPFixtureMessage {
  var id = UUID()
  var isThinking = true
  var mcpResultAuthorizationIDs: Set<UUID> = []
  var cloudProvenance: MCPFixtureProvenance? = MCPFixtureProvenance()
  var steps: [AgentStep] = []
}
struct MCPFixtureProvenance { var references: [UUID] = []; var isComplete = true }
