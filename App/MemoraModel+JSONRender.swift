import Foundation

extension MemoraModel {
  func acceptsJSONRenderInteraction(messageID: UUID?, fingerprint: String, generation: UUID,
                                   conversationID: UUID, workspaceID: String?) -> Bool {
    guard !isRestoring, !isStoreProtected, currentTeamID == workspaceID, currentTeamID == nil,
          aiWorkspaceGeneration == generation, aiConversationID == conversationID else { return false }
    guard let messageID else { return true }
    guard let message = aiMessages.first(where: { $0.id == messageID }), message.role == .assistant,
          !message.isThinking, JSONRenderSnapshot.fingerprint(message.text) == fingerprint else { return false }
    return true
  }

  func jsonRenderSnapshot(messageID: UUID?, fingerprint: String) -> JSONRenderSnapshot? {
    guard let messageID, let snapshot = aiMessages.first(where: { $0.id == messageID })?.generatedUI,
          snapshot.isValid, snapshot.fingerprint == fingerprint else { return nil }
    return snapshot
  }

  func previousJSONRenderSpec(before messageID: UUID?) -> [String: Any]? {
    guard let messageID, let index = aiMessages.firstIndex(where: { $0.id == messageID }),
          let snapshot = aiMessages[..<index].reversed().compactMap({ message -> JSONRenderSnapshot? in
            guard let value = message.generatedUI, value.isValid,
                  value.fingerprint == JSONRenderSnapshot.fingerprint(message.text) else { return nil }
            return value
          }).first,
          let data = snapshot.specJSON.data(using: .utf8),
          var spec = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let state = snapshot.stateJSON.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: state) {
      spec["state"] = value
    }
    return spec
  }

  func saveJSONRenderSnapshot(_ body: [String: Any], messageID: UUID, fingerprint: String,
                             generation: UUID, conversationID: UUID, workspaceID: String?) {
    guard acceptsJSONRenderInteraction(messageID: messageID, fingerprint: fingerprint,
      generation: generation, conversationID: conversationID, workspaceID: workspaceID),
      let index = aiMessages.firstIndex(where: { $0.id == messageID }),
      let snapshot = JSONRenderSnapshot.make(body: body, fingerprint: fingerprint),
      aiMessages[index].generatedUI != snapshot else { return }
    aiMessages[index].generatedUI = snapshot
    if let entry = aiHistory.first(where: { $0.sourceMessageID == messageID }) {
      saveJSONRenderHistorySnapshot(snapshot, entryID: entry.id)
    }
  }

  func saveJSONRenderHistorySnapshot(_ snapshot: JSONRenderSnapshot, entryID: UUID) {
    guard !isRestoring, !isStoreProtected, currentTeamID == nil, snapshot.isValid,
          let index = aiHistory.firstIndex(where: { $0.id == entryID }),
          JSONRenderSnapshot.fingerprint(aiHistory[index].answer) == snapshot.fingerprint,
          aiHistory[index].generatedUI != snapshot else { return }
    aiHistory[index].generatedUI = snapshot
    persistAIHistory()
  }

  func stageJSONRenderQuestion(_ prompt: String) -> Bool {
    guard !isRestoring, !isStoreProtected, !isAIChatResponding, composerDraftFailure == nil,
          composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          composerAttachment == nil, composerMentions.isEmpty, !prompt.isEmpty,
          prompt.utf8.count <= 32_000 else { return false }
    composerDraft = prompt
    composerFocusRequest = UUID()
    return true
  }
}
