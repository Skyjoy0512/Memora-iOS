import Foundation

extension MemoraModel {
  var agentPromptSuggestions: [AgentPromptSuggestion] {
    guard currentTeamID == nil, aiPersonScopeID == nil, !isRestoring, !isStoreProtected else { return [] }
    // A title placed in a draft could later be sent to a cloud model. Apply the
    // stricter cloud boundary even when the currently selected model is local.
    let record = meetings.lazy.filter {
      !SampleContent.isSample(meetingID: $0.id)
        && self.allowsRecordAccess($0.id, purpose: .cloudAI)
        && (!$0.transcript.isEmpty || !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || ($0.status == .ready && !$0.summary.isEmpty))
    }.max { lhs, rhs in
      lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
    }
    let task = tasks.lazy.filter {
      !$0.isCompleted && !SampleContent.isSample(task: $0) && self.allowsTaskAccess($0, purpose: .cloudAI)
    }.min { lhs, rhs in
      let left = lhs.dueDate ?? .distantFuture
      let right = rhs.dueDate ?? .distantFuture
      return left == right ? lhs.id.uuidString < rhs.id.uuidString : left < right
    }
    return AgentPromptSuggestion.make(recordID: record?.id, recordTitle: record?.displayTitle,
                                      taskID: task?.id, taskTitle: task?.title)
  }

  @discardableResult
  func selectAgentSuggestion(_ suggestion: AgentPromptSuggestion) -> Bool {
    guard aiMessages.isEmpty, !isAIChatResponding, composerDraft.isEmpty, composerAttachment == nil,
          agentPromptSuggestions.contains(suggestion) else { return false }
    // Revalidate access and the untouched composer before dispatching or staging.
    if suggestion.sendsOnSelection { return sendAIChat(suggestion.prompt) }
    composerDraft = suggestion.prompt
    composerFocusRequest = UUID()
    return true
  }
}
