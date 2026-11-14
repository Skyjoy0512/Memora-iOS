import Foundation

@MainActor
final class MemoraModel {
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var aiChatRequestID: UUID? = UUID()
  var isRestoring = false
  var isStoreProtected = false
  var cloudAuthorized = true
  var gmailAuthorized = true
  var pluginAvailable = true
  var message = NotionFixtureMessage()
  var hasMessage = true
  var notionPermissionRevision = UUID()
  var gmailPermissionRevision = UUID()
  var mcpPermissionRevision = UUID()
  var mcpServers: [MCPServerConfig] = []
  var activeMCPTools: [String: MCPTool] = [:]
  var disabledIntegrationIDs: [String] = []
  var agentPluginPolicies: [UUID: AIPluginExecutionPolicy] = [:]
  var agentBlockedExternalTools: [UUID: Set<String>] = [:]
  var meetings: [Meeting] = []
  var tasks: [MemoraTask] = []
  var approvals = 0
  var approves = true
  var onApproval: (() async -> Void)?

  func invalidateAICalendarContext() { preconditionFailure("Calendar is covered by CalendarInterfaceChecks") }
  var recordedReads: [RecordPrivacyTarget] = []

  func agentMessage(_ id: UUID) -> NotionFixtureMessage? { hasMessage && message.id == id ? message : nil }
  func isCloudSessionAuthorized(_ id: UUID) -> Bool { cloudAuthorized && gmailAuthorized && agentMessage(id) != nil }
  func gmailResultsAreCurrent(_ id: UUID) -> Bool { gmailAuthorized && agentMessage(id) != nil }
  func pluginCallIsPermitted(_ call: AgentToolCall, messageID: UUID) -> Bool {
    pluginAvailable && (agentPluginPolicies[messageID]?.permits(call.name, arguments: call.arguments) ?? true)
  }
  func toolRegistry() -> AIToolRegistry {
    var registry = AIToolRegistry()
    let tool = AgentTool.saveToNotion
    _ = registry.register(.init(id: "memora:" + tool.rawValue, name: tool.rawValue, summary: tool.summary,
      inputSchema: try! JSONSerialization.data(withJSONObject: tool.inputSchema), provider: .directAPI,
      requiredPermissions: ["memora.write"], risk: .write, isAvailable: true, isEnabled: integrationIsEnabled("notion")))
    return registry
  }
  static func meetings(in scope: AIChatScope, from meetings: [Meeting]) -> [Meeting] {
    scope == .projects ? meetings.filter { $0.spaceID != nil } : meetings
  }
  func allowsTaskAccess(_ task: MemoraTask, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard !isRestoring, !isStoreProtected else { return false }
    return RecordAccessPolicy.allowsRelated(task.privacy, parentID: task.meetingID,
      parentPrivacy: task.meetingID.flatMap { id in meetings.first { $0.id == id }?.effectivePrivacy }, purpose: purpose, inheritsParent: true)
  }
  func permittedTasks(for purpose: RecordAccessPolicy.Purpose, scope: AIChatScope) -> [MemoraTask] {
    tasks.filter { task in Self.meetings(in: scope, from: meetings).contains { $0.id == task.meetingID } && allowsTaskAccess(task, purpose: purpose) }
  }
  func recordCloudReads(_ targets: [RecordPrivacyTarget], messageID: UUID) { recordedReads += targets }
  func requestAgentApproval(_ approval: AgentApproval, changesData: Bool = true) async -> Bool {
    precondition(changesData)
    approvals += 1; await onApproval?(); return approves
  }
  func beginAgentStep(_ step: AgentStep, on id: UUID) -> UUID { message.steps.append(step); return step.id }
  func finishAgentStep(_ id: UUID, on messageID: UUID, state: AgentStep.State, detail: String? = nil) {
    guard hasMessage, message.id == messageID, let index = message.steps.firstIndex(where: { $0.id == id }) else { return }
    message.steps[index].state = state; message.steps[index].detail = detail
  }
}

struct Meeting: Hashable {
  var id = UUID()
  var title = "PRIVATE_FIXTURE_MEETING"
  var createdAt = Date(timeIntervalSince1970: 1_700_000_000)
  var duration: TimeInterval = 60
  var source = FixtureMeetingSource()
  var summary = "Fixture summary"
  var decisions = (0..<220).map { "Decision \($0)" }
  var openQuestions: [String] = []
  var spaceID: UUID?
  var privacy: RecordPrivacy = {
    var value = RecordPrivacy(classification: .personal); value.allowsCloudAI = true; return value
  }()
  var displayTitle: String { title }
  var effectivePrivacy: RecordPrivacy { privacy }
}
struct FixtureMeetingSource: Hashable { var label: String { "Fixture" } }
struct NotionFixtureMessage { var id = UUID(); var isThinking = true; var cloudProvenance: Bool? = true; var steps: [AgentStep] = [] }
enum MemoraFormat { static func duration(_ value: TimeInterval) -> String { "60s" } }
@MainActor final class GmailService { static let shared = GmailService(); static let isConfigured = false; var isConnected = false }
enum WebResearchClient { static let keyName = "no-live-key" }
enum KeychainStore {
  static var value: String? = "fixture-token"
  static var fails = false
  static func has(_ key: String) -> Bool { false }
  static func string(forKey key: String) -> String? { preconditionFailure("No live credential reads") }
  static func set(_ token: String?, forKey key: String) -> Bool {
    guard !fails else { return false }; value = token; return true
  }
}
