import Foundation

/// Calendar permission belongs to one live request, including while its
/// approval card or EventKit read is suspended. It is never restored from history.
@MainActor
struct CalendarAgentReadContext {
  let revision: UUID
  private let conversation: AgentConversationExecutionContext
  private let call: AgentToolCall
  private let messageID: UUID

  init?(in model: MemoraModel, call: AgentToolCall, messageID: UUID) {
    guard call.tool == .readCalendar,
          let conversation = AgentConversationExecutionContext(in: model, messageID: messageID,
            requiresCloudAuthorization: model.agentMessage(messageID)?.cloudProvenance != nil) else { return nil }
    self.conversation = conversation
    self.call = call
    self.messageID = messageID
    revision = model.calendarContextRevision
    guard isCurrent(in: model) else { return nil }
  }

  func ownsMessage(in model: MemoraModel) -> Bool { conversation.ownsMessage(in: model) }

  func isCurrent(in model: MemoraModel) -> Bool {
    guard conversation.isCurrent(in: model), model.calendarContextRevision == revision,
          CalendarService.access == .granted, model.integrationIsEnabled("calendar"),
          !model.agentBlockedExternalTools[messageID, default: []].contains(call.name),
          let message = model.agentMessage(messageID), model.calendarReadIsCurrent(message.calendarReadSnapshot),
          model.gmailResultsAreCurrent(messageID), model.mcpResultsAreCurrent(messageID),
          model.pluginCallIsPermitted(call, messageID: messageID),
          model.toolRegistry().permits(call.name, arguments: call.arguments, policy: model.agentPluginPolicies[messageID]) else { return false }
    return model.agentPluginPolicies[messageID].map(model.personPolicyIsCurrent) ?? true
  }
}
