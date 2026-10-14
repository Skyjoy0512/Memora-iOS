import Foundation

extension MemoraModel {
  func canUseInterfaceTask(_ id: UUID, messageID: UUID) -> Bool {
    guard !isRestoring, !isStoreProtected, let message = agentMessage(messageID),
          message.interfaceWorkspaceID == currentTeamID, message.interfaceTaskIDs.contains(id), let task = task(id: id) else { return false }
    if message.cloudProvenance != nil { return allowsTaskAccess(task, purpose: .cloudAI) && isCloudSessionAuthorized(messageID) }
    return true
  }

  /// The model can propose a control, but its payload cannot execute a tool.
  /// Tapping uses the original message's policy, registry and approval card.
  func completeInterfaceTask(_ id: UUID, messageID: UUID) {
    guard !isAIChatResponding, canUseInterfaceTask(id, messageID: messageID), task(id: id)?.isCompleted == false,
          let message = agentMessage(messageID) else { return }
    let requestID = UUID()
    aiChatRequestID = requestID
    isAIChatResponding = true
    updateAgentMessage(messageID) { $0.isThinking = true; $0.createdAt = .now; $0.finishedAt = nil }
    aiChatTask = Task { [weak self] in
      guard let self else { return }
      let call = AgentToolCall(id: UUID().uuidString, name: AgentTool.updateTasks.rawValue,
        arguments: ["updates": [["id": id.uuidString, "is_completed": true]]])
      let outcome = await runAgentTool(call, messageID: messageID, scope: .all, compact: message.cloudProvenance == nil)
      guard aiChatRequestID == requestID else { return }
      updateAgentMessage(messageID) { $0.isThinking = false; $0.finishedAt = .now }
      isAIChatResponding = false
      aiChatTask = nil
      aiChatRequestID = nil
      if outcome.isError { aiMessages.append(AIChatMessage(role: .assistant, text: outcome.text)) }
    }
  }
}
