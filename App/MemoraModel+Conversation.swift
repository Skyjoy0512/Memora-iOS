import Foundation

extension MemoraModel {
  func saveComposerAttachment() {
    guard conversationPersistenceReady, !isRestoring, !isStoreProtected else { return }
    guard let reference = composerAttachment.flatMap(AIAttachmentFileReference.init),
          let data = try? JSONEncoder().encode(reference), let text = String(data: data, encoding: .utf8) else {
      DraftStore.clear("composer.attachment.v1")
      return
    }
    DraftStore.save(text, key: "composer.attachment.v1")
  }

  func restoreAIRequestToComposer(_ message: AIChatMessage, focusesInput: Bool = true) {
    guard message.role == .user else { return }
    composerDraft = message.text
    composerMentions = message.mentions.filter { $0.isValid(in: message.text) && message.pluginIDs.contains($0.pluginID) }
    composerAttachment = message.attachment
    if focusesInput { composerFocusRequest = UUID() }
  }

  func recoverFailedAttachmentRequest(_ messageID: UUID) {
    guard !isRestoring, !isStoreProtected, composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          composerAttachment == nil, let message = agentMessage(messageID), message.attachment != nil else { return }
    // Recover a draft only; a failed or uncertain operation is never resubmitted.
    restoreAIRequestToComposer(message, focusesInput: false)
  }

  func authoredMentions(for text: String, pluginIDs: [String]) -> [ComposerMention] {
    ComposerMention.reconciled(composerMentions, from: composerDraft, to: text)
      .filter { pluginIDs.contains($0.pluginID) }
  }
  static func conversationStorageKey(workspaceID: String?) -> String {
    StorageKey.activeAIConversation + "." + (workspaceID.map { Data($0.utf8).base64EncodedString() } ?? "personal")
  }

  func scheduleConversationSave() {
    guard conversationPersistenceReady else { return }
    conversationSaveTask?.cancel()
    conversationSaveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled, let self else { return }
      persistActiveAIConversation()
    }
  }

  func persistActiveAIConversation() {
    guard conversationPersistenceReady, !isRestoring, !isStoreProtected else { return }
    conversationSaveTask?.cancel()
    conversationSaveTask = nil
    let snapshot = AIConversationSnapshot(messages: aiMessages, workspaceID: currentTeamID, personID: aiPersonScopeID, conversationID: aiConversationID)
    saveConversationSnapshot(snapshot)
  }

  private func saveConversationSnapshot(_ snapshot: AIConversationSnapshot) {
    guard snapshot.isValid else {
      persistenceFailureMessage = "会話が保存上限を超えています。完了した回答は履歴から確認できます。"
      return
    }
    persistInBackground(snapshot, forKey: Self.conversationStorageKey(workspaceID: snapshot.workspaceID))
  }

  func restoreActiveAIConversation() {
    let key = Self.conversationStorageKey(workspaceID: currentTeamID)
    switch RecordStore.load(key) {
    case .absent: break
    case .failed:
      isStoreProtected = true
      loadFailureMessage = storeProtectedMessage
    case .data(let data):
      do {
        let snapshot = try AIConversationSnapshot.decode(data, workspaceID: currentTeamID)
        aiMessages = snapshot.restoredMessages()
        aiPersonScopeID = snapshot.personID
        aiConversationID = snapshot.conversationID ?? UUID()
      } catch {
        // A malformed resume document cannot erase history or records.
        loadFailureMessage = "前回の会話を復元できませんでした。保存済みの履歴から開いてください。"
        if !RecordStore.quarantine(data, key: key) { isStoreProtected = true }
      }
    }
  }

  func didChangeConversationWorkspace(from previous: String?) {
    invalidateAIWorkspaceExecution()
    for job in webResearchJobs.values { job.cancel() }
    guard conversationPersistenceReady else { return }
    conversationSaveTask?.cancel()
    let previousSnapshot = AIConversationSnapshot(messages: aiMessages, workspaceID: previous, personID: aiPersonScopeID, conversationID: aiConversationID)
    if previousSnapshot.isValid {
      // This infrequent navigation boundary must land before an immediate switch back.
      persistNow(previousSnapshot, forKey: Self.conversationStorageKey(workspaceID: previous))
    }
    conversationPersistenceReady = false
    for id in runningResidentIDs { cancelResident(id) }
    startNewAIChat()
    restoreActiveAIConversation()
    conversationPersistenceReady = true
  }
}
