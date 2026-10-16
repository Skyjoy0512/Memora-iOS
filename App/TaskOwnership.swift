import Foundation

enum TaskOwnership {
  static func isMine(_ task: MemoraTask, names: [String]) -> Bool {
    if let owned = task.ownedByMe { return owned }
    if task.relationships.assigneePersonID != nil { return false }
    let owner = normalized(task.assignee ?? "")
    if owner.isEmpty { return task.meetingID == nil }
    let identities = names + ["Me", "自分", "私", "わたし"]
    return identities.map(normalized).filter { !$0.isEmpty }.contains(owner)
  }

  /// Normalize the person's identities once for a list, retaining the same
  /// explicit ownership and unassigned-task rules as the individual lookup.
  static func ownedTasks(_ tasks: [MemoraTask], names: [String]) -> [MemoraTask] {
    let identities = normalizedIdentities(names)
    return tasks.filter { isMine($0, identities: identities) }
  }

  private static func isMine(_ task: MemoraTask, identities: Set<String>) -> Bool {
    if let owned = task.ownedByMe { return owned }
    if task.relationships.assigneePersonID != nil { return false }
    let owner = normalized(task.assignee ?? "")
    if owner.isEmpty { return task.meetingID == nil }
    return identities.contains(owner)
  }

  private static func normalizedIdentities(_ names: [String]) -> Set<String> {
    Set((names + ["Me", "自分", "私", "わたし"]).map(normalized).filter { !$0.isEmpty })
  }

  private static func normalized(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
  }
}
