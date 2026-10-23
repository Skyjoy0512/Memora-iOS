import Foundation

/// An ephemeral binding to the conversation that authorized an external call.
@MainActor
struct MCPAgentExecutionContext {
  private let conversation: AgentConversationExecutionContext
  private let permissionRevision: UUID

  init?(in model: MemoraModel, messageID: UUID) {
    guard let conversation = AgentConversationExecutionContext(in: model, messageID: messageID) else { return nil }
    self.conversation = conversation
    permissionRevision = model.mcpPermissionRevision
    guard isCurrent(in: model) else { return nil }
  }

  func ownsMessage(in model: MemoraModel) -> Bool {
    conversation.ownsMessage(in: model)
  }

  func isCurrent(in model: MemoraModel) -> Bool {
    bindingIsCurrent(in: model) && conversation.isCurrent(in: model)
  }

  // Result grants use the same binding without recursively checking themselves.
  func bindingIsCurrent(in model: MemoraModel) -> Bool {
    conversation.bindingIsCurrent(in: model) && model.mcpPermissionRevision == permissionRevision
  }
}
