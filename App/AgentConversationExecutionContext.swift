import Foundation

/// A transient owner shared by integrations; never an authorization restored from history.
@MainActor
struct AgentConversationExecutionContext {
  private let workspaceID: String?
  private let generation: UUID
  private let requestID: UUID
  private let messageID: UUID
  private let policy: AIPluginExecutionPolicy?
  private let requiresCloudAuthorization: Bool

  init?(in model: MemoraModel, messageID: UUID, requiresCloudAuthorization: Bool = true) {
    guard let requestID = model.aiChatRequestID else { return nil }
    workspaceID = model.currentTeamID
    generation = model.aiWorkspaceGeneration
    self.requestID = requestID
    self.messageID = messageID
    policy = model.agentPluginPolicies[messageID]
    self.requiresCloudAuthorization = requiresCloudAuthorization
    guard bindingIsCurrent(in: model) else { return nil }
  }

  func ownsMessage(in model: MemoraModel) -> Bool {
    model.currentTeamID == workspaceID && model.aiWorkspaceGeneration == generation &&
      model.aiChatRequestID == requestID && model.agentMessage(messageID)?.isThinking == true
  }

  func bindingIsCurrent(in model: MemoraModel) -> Bool {
    !Task.isCancelled && workspaceID == nil && ownsMessage(in: model) &&
      !model.isRestoring && !model.isStoreProtected && model.agentPluginPolicies[messageID] == policy
  }

  func isCurrent(in model: MemoraModel) -> Bool {
    bindingIsCurrent(in: model) && (!requiresCloudAuthorization || model.isCloudSessionAuthorized(messageID))
  }
}
