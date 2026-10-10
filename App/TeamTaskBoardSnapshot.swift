import Foundation

struct TeamTaskBoardSnapshot: Sendable {
  var teamID: String
  var revision: String
  var tasks: [MemoraTask]
  var ownTaskIDs: Set<UUID>

  var isValid: Bool {
    let identifiers = Set(tasks.map(\.id))
    return !revision.isEmpty && identifiers.count == tasks.count
      && ownTaskIDs.isSubset(of: identifiers)
      && tasks.allSatisfy { TaskHierarchy.canParent($0.id, under: $0.relationships.parentID, tasks: tasks) }
  }
}
