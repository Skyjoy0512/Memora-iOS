import Foundation

extension MemoraModel {
  /// Live is a local-only conversation, independent of the normal cloud choice.
  /// This path has no tools, URL intake or provider/API fallback.
  @discardableResult
  func sendLocalVoiceChat(_ question: String) -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected, !isAIChatResponding,
          LocalVoiceModel.isInstalled else { return false }
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return false }
    let history = aiMessages.suffix(8).filter { !$0.isThinking && !$0.text.isEmpty }
      .map { ($0.role == .user ? "利用者: " : "Memora: ") + $0.text }.joined(separator: "\n")
    let requestID = UUID()
    let workspace = aiWorkspaceGeneration
    let conversation = aiConversationID
    aiChatRequestID = requestID
    aiMessages.append(AIChatMessage(role: .user, text: question))
    var reply = AIChatMessage(role: .assistant, text: "", isThinking: true)
    reply.searchFinished = true
    let replyID = reply.id
    aiMessages.append(reply)
    isAIChatResponding = true
    aiChatTask?.cancel()
    aiChatTask = Task { [weak self] in
      guard let self else { return }
      let isCurrent: @MainActor () -> Bool = {
        self.aiChatRequestID == requestID && self.aiWorkspaceGeneration == workspace &&
          self.aiConversationID == conversation && self.currentTeamID == nil &&
          !self.isRestoring && !self.isStoreProtected && !Task.isCancelled
      }
      let result = await LocalVoiceLLM.shared.answer(question: question, context: "", history: history,
        onText: { [weak self] text in
          guard isCurrent() else { return }
          self?.updateAgentMessage(replyID) { $0.text = text }
        }, authorize: isCurrent)
      guard isCurrent() else { return }
      let text: String
      switch result {
      case .answer(let answer): text = answer
      case .failure(let failure): text = failure.message
      }
      self.updateAgentMessage(replyID) {
        $0.text = text
        $0.isThinking = false
        $0.finishedAt = .now
        $0.details = AIAnswerDetails(scopeLabel: "ローカル音声会話", engineLabel: "ローカルLLM",
          modelLabel: LocalVoiceModel.name, sourceCount: 0, generatedAt: .now)
      }
      self.isAIChatResponding = false
      self.aiChatRequestID = nil
      self.aiChatTask = nil
      if case .answer = result {
        self.saveAIExchange(question: question, answer: text, scopeLabel: "ローカル音声会話",
          engineLabel: "ローカルLLM", modelLabel: LocalVoiceModel.name)
      }
      self.persistActiveAIConversation()
    }
    return true
  }
}
