import Foundation

/// Production integration/approval orchestration, context and Gmail service run;
/// only conversation state, registry assembly and the approval UI are modeled.
@MainActor
final class MemoraModel {
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var aiChatRequestID: UUID? = UUID()
  var isRestoring = false
  var isStoreProtected = false
  var cloudAuthorized = true
  var pluginAvailable = true
  var message = GmailFixtureMessage()
  var hasMessage = true
  var gmailPermissionRevision = UUID()
  var notionPermissionRevision = UUID()
  var gmailResultAuthorizations: [UUID: GmailAgentReadContext] = [:]
  var mcpPermissionRevision = UUID()
  var activeMCPTools: [String: MCPTool] = [:]
  var disabledIntegrationIDs: [String] = []
  var agentPluginPolicies: [UUID: AIPluginExecutionPolicy] = [:]
  var agentBlockedExternalTools: [UUID: Set<String>] = [:]
  var approvals = 0
  var approves = true
  var onApproval: (() async -> Void)?

  func agentMessage(_ id: UUID) -> GmailFixtureMessage? { hasMessage && message.id == id ? message : nil }
  func isCloudSessionAuthorized(_ id: UUID) -> Bool { cloudAuthorized && gmailResultsAreCurrent(id) }
  func updateAgentMessage(_ id: UUID, _ update: (inout GmailFixtureMessage) -> Void) {
    guard hasMessage, message.id == id else { return }; update(&message)
  }
  func pluginCallIsPermitted(_ call: AgentToolCall, messageID: UUID) -> Bool {
    pluginAvailable && (agentPluginPolicies[messageID]?.permits(call.name, arguments: call.arguments) ?? true)
  }
  func toolRegistry() -> AIToolRegistry {
    var registry = AIToolRegistry()
    for tool in [AgentTool.searchEmail, .readEmail] {
      _ = registry.register(.init(id: "memora:" + tool.rawValue, name: tool.rawValue, summary: tool.summary,
        inputSchema: try! JSONSerialization.data(withJSONObject: tool.inputSchema), provider: .directAPI,
        requiredPermissions: ["memora.read"], risk: .read, isAvailable: true, isEnabled: integrationIsEnabled("gmail")))
    }
    return registry
  }
  func requestAgentApproval(_ approval: AgentApproval, changesData: Bool = true) async -> Bool {
    precondition(!changesData)
    approvals += 1; await onApproval?(); return approves
  }
  func beginAgentStep(_ step: AgentStep, on id: UUID) -> UUID { message.steps.append(step); return step.id }
  func finishAgentStep(_ id: UUID, on messageID: UUID, state: AgentStep.State, detail: String? = nil, results: [AgentStep.Result] = []) {
    guard hasMessage, message.id == messageID, let index = message.steps.firstIndex(where: { $0.id == id }) else { return }
    message.steps[index].state = state; message.steps[index].detail = detail; message.steps[index].results = results
  }
  static func agentDate(_ date: Date) -> String { date.description }
}

struct GmailFixtureMessage {
  var id = UUID()
  var isThinking = true
  var gmailResultAuthorizationIDs: Set<UUID> = []
  var cloudProvenance: GmailFixtureProvenance? = .init()
  var steps: [AgentStep] = []
}
struct GmailFixtureProvenance { var isComplete = true }
@MainActor enum KeychainStore { static func has(_ key: String) -> Bool { false } }
enum WebResearchClient { static let keyName = "no-live-key" }
