import Foundation

enum PersonTaskAssociation {
  static func isAssigned(_ task: MemoraTask, to personID: UUID) -> Bool {
    task.relationships.assigneePersonID == personID
  }

  static func nameMatches(_ task: MemoraTask, normalizedName: String, isUnique: Bool) -> Bool {
    guard isUnique, !normalizedName.isEmpty, task.relationships.assigneePersonID == nil,
          task.ownedByMe != true, let name = task.assignee else { return false }
    return PersonIdentity.normalized(name) == normalizedName
  }
}
