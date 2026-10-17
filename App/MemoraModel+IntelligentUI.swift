import Foundation

extension MemoraModel {
  func canOpenInterfaceReference(_ target: AIInterfaceReferenceTarget, messageID: UUID) -> Bool {
    guard canUseInterfaceContext(messageID: messageID), let message = agentMessage(messageID) else { return false }
    switch target {
    case .document(let id):
      guard message.documentIDs.contains(id), let document = document(id: id) else { return false }
      return document.provenance.map { $0.isValid && $0.workspaceID == currentTeamID } ?? true
    case .meeting(let id):
      return message.sources.contains { $0.meetingID == id }
        && canOpenArtifactSource(.record(.meeting(id)), workspaceID: message.interfaceWorkspaceID)
    case .project(let id):
      return message.interfaceProjectIDs.contains(id) && space(id: id) != nil
    }
  }

  func interfaceMailDraft(_ id: UUID, messageID: UUID) -> MailDraft? {
    guard canUseInterfaceContext(messageID: messageID) else { return nil }
    return mailDrafts.first { $0.id == id && $0.sourceMessageID == messageID && $0.workspaceID == currentTeamID }
  }

  func interfaceRenderContext(messageID: UUID?, taskIDs: Set<UUID>) -> (message: AIChatMessage?, taskIDs: Set<UUID>, sources: [UUID: AIChatSource]) {
    guard let messageID, canUseInterfaceContext(messageID: messageID), let message = agentMessage(messageID) else {
      return (nil, [], [:])
    }
    let allowedTasks = Set(taskIDs.intersection(message.interfaceTaskIDs).filter { id in
      guard let task = task(id: id) else { return false }
      return message.cloudProvenance == nil || allowsTaskAccess(task, purpose: .cloudAI)
    })
    let sources = Dictionary(message.sources.map { ($0.meetingID, $0) }, uniquingKeysWith: { first, _ in first })
    return (message, allowedTasks, sources)
  }

  func canUseInterfaceContext(messageID: UUID) -> Bool {
    // These IDs resolve in the personal SQLite store, never in an unconnected team backend.
    guard currentTeamID == nil, !isRestoring, !isStoreProtected, let message = agentMessage(messageID),
          message.interfaceWorkspaceID == currentTeamID else { return false }
    return message.cloudProvenance == nil || isCloudSessionAuthorized(messageID)
  }

  func canUseInterfaceTask(_ id: UUID, messageID: UUID) -> Bool {
    guard canUseInterfaceContext(messageID: messageID), let message = agentMessage(messageID),
          message.interfaceTaskIDs.contains(id), let task = task(id: id) else { return false }
    if message.cloudProvenance != nil { return allowsTaskAccess(task, purpose: .cloudAI) }
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
