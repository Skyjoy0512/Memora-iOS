import Foundation

extension MemoraModel {
  func projectChatExecutionIsCurrent(_ id: UUID, requestID: UUID, generation: UUID) -> Bool {
    !Task.isCancelled && aiWorkspaceGeneration == generation && projectChatRequestIDs[id] == requestID
  }

  /// A late cancelled task must not remove the replacement task's presentation.
  func finishProjectChatExecution(_ id: UUID, requestID: UUID) {
    guard projectChatRequestIDs[id] == requestID else { return }
    projectChatRequestIDs.removeValue(forKey: id)
    projectChatBusyIDs.remove(id)
    projectChatStages.removeValue(forKey: id)
    projectChatPartialAnswers.removeValue(forKey: id)
    projectChatJobs.removeValue(forKey: id)
  }

  func cancelProjectChat(_ id: UUID, message: String = "回答を停止しました。自動で再送はしません。") {
    projectChatJobs[id]?.cancel()
    if let requestID = projectChatRequestIDs[id] {
      finishProjectChatExecution(id, requestID: requestID)
    }
    if var thread = projectChat(id: id), thread.pendingMessageID != nil {
      thread.pendingMessageID = nil
      thread.lastFailure = message
      _ = storeProjectChat(thread)
    }
  }

  func invalidateAIWorkspaceExecution() {
    // Identity alone cannot detect A → B → A while a read is suspended.
    aiWorkspaceGeneration = UUID()
    for id in Array(projectChatRequestIDs.keys) {
      cancelProjectChat(id, message: "ワークスペースが変わったため停止しました。自動で再送はしません。")
    }
  }
}
