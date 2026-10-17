import Foundation

extension MemoraModel {
  /// The longest a single memory may be, so one entry cannot crowd the rest.
  static let aiMemoryCharacterLimit = 200

  // MARK: - Memories

  /// Keeps something about the person. Returns false for an empty text or one
  /// already remembered.
  @discardableResult
  func addAIMemory(_ text: String, origin: AIMemory.Origin, sourceReference: String = "settings") -> Bool {
    let trimmed = String(
      text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.aiMemoryCharacterLimit)
    )
    guard !trimmed.isEmpty,
          !aiMemories.contains(where: { $0.workspaceID == currentTeamID && $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
      return false
    }
    guard !isRestoring, isStoreWritable(), aiMemories.count < 5_000 else { return false }
    var candidate = aiMemories
    let now = Date.now
    let semantic = AIMemory.Semantic(value: trimmed, sourceReference: sourceReference,
      observedAt: now, updatedAt: now, validFrom: now, workspaceID: currentTeamID)
    candidate.insert(AIMemory(id: UUID(), text: trimmed, origin: origin, createdAt: now, semantic: semantic), at: 0)
    return storeAIMemories(candidate)
  }

  var visibleAIMemories: [AIMemory] { aiMemories.filter { $0.workspaceID == currentTeamID } }

  @discardableResult
  func storeAIMemories(_ candidate: [AIMemory]) -> Bool {
    guard !isRestoring, isStoreWritable(), persistNow(candidate, forKey: StorageKey.aiMemories) else { return false }
    aiMemories = candidate
    return true
  }

  func canEditAIMemory(_ original: AIMemory) -> Bool {
    !isRestoring && !isStoreProtected && original.workspaceID == currentTeamID
      && aiMemories.contains(original)
  }

  @discardableResult
  func saveAIMemoryEdit(_ plan: AIMemoryEditPlan) -> Bool {
    guard !isRestoring, isStoreWritable(),
          let candidate = plan.applying(to: aiMemories, workspaceID: currentTeamID) else { return false }
    return storeAIMemories(candidate)
  }

  @discardableResult
  func deleteAIMemory(_ original: AIMemory) -> Bool {
    guard canEditAIMemory(original) else { return false }
    return deleteAIMemories([original.id])
  }

  @discardableResult
  func updateAIMemory(_ id: UUID, text: String, status: AIMemory.Status = .current,
                      kind: AIMemory.Kind = .fact, sensitivity: AIMemory.Sensitivity = .standard,
                      predicate: String = "note") -> Bool {
    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.aiMemoryCharacterLimit))
    guard let index = aiMemories.firstIndex(where: { $0.id == id && $0.workspaceID == currentTeamID }) else { return false }
    if trimmed.isEmpty { return deleteAIMemories([id]) }
    var candidate = aiMemories
    candidate[index] = candidate[index].edited(text: trimmed, status: status, kind: kind,
      sensitivity: sensitivity, predicate: predicate, workspaceID: currentTeamID)
    return storeAIMemories(AIMemory.reconciling(candidate, editedID: id))
  }

  @discardableResult
  func deleteAIMemories(_ ids: Set<UUID>) -> Bool {
    storeAIMemories(aiMemories.filter { !ids.contains($0.id) || $0.workspaceID != currentTeamID })
  }

  @discardableResult
  func deleteAllAIMemories(in workspaceID: String?) -> Bool {
    guard workspaceID == currentTeamID else { return false }
    return storeAIMemories(aiMemories.filter { $0.workspaceID != workspaceID })
  }

}
