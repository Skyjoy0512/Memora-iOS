import Foundation

@MainActor
struct NotionAgentExecutionContext {
  private let conversation: AgentConversationExecutionContext
  private let export: NotionExportContext
  private let call: AgentToolCall
  private let messageID: UUID
  private let permissionRevision: UUID

  init?(in model: MemoraModel, export: NotionExportContext, call: AgentToolCall, messageID: UUID) {
    guard let conversation = AgentConversationExecutionContext(in: model, messageID: messageID,
      requiresCloudAuthorization: model.agentMessage(messageID)?.cloudProvenance != nil) else { return nil }
    self.conversation = conversation
    self.export = export
    self.call = call
    self.messageID = messageID
    permissionRevision = model.notionPermissionRevision
    guard isCurrent(in: model) else { return nil }
  }

  func ownsMessage(in model: MemoraModel) -> Bool { conversation.ownsMessage(in: model) }

  func isCurrent(in model: MemoraModel) -> Bool {
    conversation.isCurrent(in: model) && export.isCurrent(in: model) && model.gmailResultsAreCurrent(messageID) &&
      model.notionPermissionRevision == permissionRevision && model.integrationIsEnabled("notion") &&
      model.pluginCallIsPermitted(call, messageID: messageID) &&
      model.toolRegistry().permits(call.name, arguments: call.arguments, policy: model.agentPluginPolicies[messageID])
  }
}
