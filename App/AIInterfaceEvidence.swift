import Foundation

/// Resolves a structured row's optional evidence ID to a target the message
/// currently permits.
///
/// The order is fixed — meeting, then document, then project — so the same ID
/// always resolves the same way. `isPermitted` is the model's own check
/// (`canOpenInterfaceReference`), so a deleted, revoked or out-of-workspace
/// record yields no target and the row simply shows its text without a link.
/// Nothing here grants or widens access.
enum AIInterfaceEvidence {
  static func target(for id: UUID, isPermitted: (AIInterfaceReferenceTarget) -> Bool) -> AIInterfaceReferenceTarget? {
    for target: AIInterfaceReferenceTarget in [.meeting(id), .document(id), .project(id)] {
      if isPermitted(target) { return target }
    }
    return nil
  }

  static func targets(for ids: [UUID], isPermitted: (AIInterfaceReferenceTarget) -> Bool) -> [UUID: AIInterfaceReferenceTarget] {
    var resolved: [UUID: AIInterfaceReferenceTarget] = [:]
    for id in Set(ids) {
      if let target = target(for: id, isPermitted: isPermitted) { resolved[id] = target }
    }
    return resolved
  }
}
