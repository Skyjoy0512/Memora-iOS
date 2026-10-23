import Foundation

/// An ephemeral binding to the conversation that authorized an external call.
@MainActor
struct MCPAgentExecutionContext {
  private let workspaceID: String?
  private let generation: UUID
  private let requestID: UUID
  private let messageID: UUID
  private let policy: AIPluginExecutionPolicy?
  private let permissionRevision: UUID

  init?(in model: MemoraModel, messageID: UUID) {
    guard let requestID = model.aiChatRequestID else { return nil }
    workspaceID = model.currentTeamID
    generation = model.aiWorkspaceGeneration
    self.requestID = requestID
    self.messageID = messageID
    policy = model.agentPluginPolicies[messageID]
    permissionRevision = model.mcpPermissionRevision
    guard isCurrent(in: model) else { return nil }
  }

  func ownsMessage(in model: MemoraModel) -> Bool {
    model.currentTeamID == workspaceID && model.aiWorkspaceGeneration == generation &&
      model.aiChatRequestID == requestID && model.agentMessage(messageID)?.isThinking == true
  }

  func isCurrent(in model: MemoraModel) -> Bool {
    bindingIsCurrent(in: model) && model.isCloudSessionAuthorized(messageID)
  }

  // Result grants use the same binding without recursively checking themselves.
  func bindingIsCurrent(in model: MemoraModel) -> Bool {
    !Task.isCancelled && workspaceID == nil && ownsMessage(in: model) &&
      !model.isRestoring && !model.isStoreProtected &&
      model.mcpPermissionRevision == permissionRevision &&
      model.agentPluginPolicies[messageID] == policy
  }
}
