import Foundation

@MainActor
struct GmailAgentReadContext {
  private let conversation: AgentConversationExecutionContext
  private let permissionRevision: UUID
  private let connectionRevision: UUID
  private let account: String?
  private let service: GmailService
  private let call: AgentToolCall
  private let messageID: UUID

  init?(in model: MemoraModel, call: AgentToolCall, messageID: UUID, compact: Bool, service: GmailService) {
    guard call.tool == .searchEmail || call.tool == .readEmail,
          let conversation = AgentConversationExecutionContext(in: model, messageID: messageID,
            requiresCloudAuthorization: !compact || model.agentMessage(messageID)?.cloudProvenance != nil) else { return nil }
    self.conversation = conversation
    self.service = service
    self.call = call
    self.messageID = messageID
    permissionRevision = model.gmailPermissionRevision
    connectionRevision = service.connectionRevision
    account = service.connectedEmail
    guard isCurrent(in: model) else { return nil }
  }

  func ownsMessage(in model: MemoraModel) -> Bool { conversation.ownsMessage(in: model) }

  func bindingIsCurrent(in model: MemoraModel) -> Bool {
    conversation.bindingIsCurrent(in: model) && model.gmailPermissionRevision == permissionRevision &&
      model.integrationIsEnabled("gmail") && service.isConnected && service.connectionRevision == connectionRevision &&
      service.connectedEmail == account && model.pluginCallIsPermitted(call, messageID: messageID) &&
      model.toolRegistry().permits(call.name, arguments: call.arguments, policy: model.agentPluginPolicies[messageID])
  }

  func isCurrent(in model: MemoraModel) -> Bool {
    bindingIsCurrent(in: model) && conversation.isCurrent(in: model) && model.gmailResultsAreCurrent(messageID)
  }
}
