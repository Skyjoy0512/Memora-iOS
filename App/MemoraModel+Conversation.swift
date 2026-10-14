import Foundation

extension MemoraModel {
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
    let snapshot = AIConversationSnapshot(messages: aiMessages, workspaceID: currentTeamID)
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
      } catch {
        // A malformed resume document cannot erase history or records.
        loadFailureMessage = "前回の会話を復元できませんでした。保存済みの履歴から開いてください。"
        if !RecordStore.quarantine(data, key: key) { isStoreProtected = true }
      }
    }
  }

  func didChangeConversationWorkspace(from previous: String?) {
    guard conversationPersistenceReady else { return }
    conversationSaveTask?.cancel()
    let previousSnapshot = AIConversationSnapshot(messages: aiMessages, workspaceID: previous)
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
