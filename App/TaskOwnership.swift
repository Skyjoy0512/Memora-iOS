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

  /// Whether a spoken owner name is the person themselves. Used to decide which
  /// actions a verified voice is allowed to speak for.
  static func namesSelf(_ owner: String, names: [String]) -> Bool {
    let owner = normalized(owner)
    return !owner.isEmpty && normalizedIdentities(names).contains(owner)
  }

  /// `true` when the action came from the cluster the registered voice matched,
  /// `false` when it came from another cluster, and `nil` when no voice was
  /// matched, so the name-based rule stays in charge.
  static func speakerOwnership(speakerID: String, ownSpeakerID: String?) -> Bool? {
    let speakerID = speakerID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let ownSpeakerID = ownSpeakerID?.trimmingCharacters(in: .whitespacesAndNewlines),
          !ownSpeakerID.isEmpty, !speakerID.isEmpty else { return nil }
    return speakerID == ownSpeakerID
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
