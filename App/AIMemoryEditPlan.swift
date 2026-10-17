import Foundation

/// Holds the exact values shown before a multi-memory update, rather than a reusable write grant.
struct AIMemoryEditPlan {
  var original: AIMemory
  var replacement: AIMemory
  var related: [AIMemory]
  var resolvesConflicts: Bool

  static func relatedMemories(in memories: [AIMemory], to memory: AIMemory, predicate: String) -> [AIMemory] {
    let key = String(predicate.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    guard !key.isEmpty, key != "note" else { return [] }
    return memories.filter {
      $0.id != memory.id && $0.workspaceID == memory.workspaceID
        && $0.semantic?.subjectID == (memory.semantic?.subjectID ?? "user")
        && $0.semantic?.predicate == key && ![.historical, .disabled].contains($0.status)
    }
  }

  func applying(to memories: [AIMemory], workspaceID: String?) -> [AIMemory]? {
    guard original.workspaceID == workspaceID, replacement.workspaceID == workspaceID,
          replacement.id == original.id, replacement.origin == original.origin,
          replacement.createdAt == original.createdAt,
          replacement.semantic?.subjectID == (original.semantic?.subjectID ?? "user"),
          !replacement.text.isEmpty, replacement.text.count <= 200,
          replacement.semantic?.value == replacement.text,
          Set(memories.map(\.id)).count == memories.count,
          let index = memories.firstIndex(where: { $0.id == original.id }), memories[index] == original,
          Set(Self.relatedMemories(in: memories, to: replacement, predicate: replacement.semantic?.predicate ?? "note")) == Set(related),
          Set(related.map(\.id)).count == related.count else { return nil }
    var candidate = memories
    candidate[index] = replacement
    let now = replacement.updatedAt
    if resolvesConflicts {
      guard replacement.status == .current, !related.isEmpty else { return nil }
      let ids = Set(related.map(\.id))
      for other in candidate.indices where ids.contains(candidate[other].id) {
        candidate[other] = candidate[other].changingStatus(to: .historical, now: now)
      }
      return candidate
    }
    return AIMemory.reconciling(candidate, editedID: original.id, now: now)
  }
}
