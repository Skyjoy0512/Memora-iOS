import Foundation

struct AIMemoryEditDraft {
  var text: String
  var status: AIMemory.Status
  var kind: AIMemory.Kind
  var sensitivity: AIMemory.Sensitivity
  var predicate: String
  var resolvesConflicts = false

  init(memory: AIMemory) {
    text = memory.text
    status = memory.status
    kind = memory.semantic?.type ?? .fact
    sensitivity = memory.semantic?.sensitivity ?? .standard
    predicate = memory.semantic?.predicate ?? "note"
  }

  func plan(for original: AIMemory, related: [AIMemory], now: Date = .now) -> AIMemoryEditPlan {
    let replacement = original.edited(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
      status: status, kind: kind, sensitivity: sensitivity, predicate: predicate,
      workspaceID: original.workspaceID, now: now)
    return .init(original: original, replacement: replacement, related: related,
      resolvesConflicts: resolvesConflicts && status == .current && !related.isEmpty)
  }
}
