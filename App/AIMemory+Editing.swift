import Foundation

extension AIMemory {
  func edited(text: String, status: Status, kind: Kind, sensitivity: Sensitivity, predicate: String,
              workspaceID: String?, now: Date = .now) -> Self {
    var result = self
    var history = revisions ?? []
    history.append(.init(text: self.text, semantic: semantic, supersededAt: now))
    result.revisions = Array(history.suffix(30))
    result.text = text
    var value = semantic ?? .init(value: self.text, sourceReference: "legacy:\(id)", observedAt: createdAt, updatedAt: createdAt, validFrom: createdAt)
    value.value = text; value.updatedAt = now; value.validFrom = now
    value.validTo = status == .historical || status == .disabled ? now : nil
    value.status = status; value.type = kind; value.sensitivity = sensitivity
    value.predicate = String(predicate.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    if value.predicate.isEmpty { value.predicate = "note" }
    value.userConfirmed = true; value.sourceReference = "user-edit:\(id)"; value.workspaceID = workspaceID
    result.semantic = value
    return result
  }

  func changingStatus(to status: Status, now: Date) -> Self {
    guard self.status != status, var value = semantic else { return self }
    var result = self
    result.revisions = Array(((revisions ?? []) + [.init(text: text, semantic: semantic, supersededAt: now)]).suffix(30))
    value.status = status
    value.updatedAt = now
    value.validTo = status == .historical || status == .disabled ? now : nil
    result.semantic = value
    return result
  }

  static func reconciling(_ memories: [Self], editedID: UUID, now: Date = .now) -> [Self] {
    guard let index = memories.firstIndex(where: { $0.id == editedID }),
          let value = memories[index].semantic, value.predicate != "note", value.status == .current else { return memories }
    var result = memories
    for other in result.indices where other != index {
      guard let old = result[other].semantic, old.workspaceID == value.workspaceID,
            old.subjectID == value.subjectID, old.predicate == value.predicate,
            [.current, .conflicted].contains(old.status), old.value != value.value else { continue }
      result[other] = result[other].changingStatus(to: .conflicted, now: now)
      result[index] = result[index].changingStatus(to: .conflicted, now: now)
    }
    return result
  }
}
