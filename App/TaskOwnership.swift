import Foundation

enum TaskOwnership {
  static func isMine(_ task: MemoraTask, names: [String]) -> Bool {
    if let owned = task.ownedByMe { return owned }
    let owner = normalized(task.assignee ?? "")
    if owner.isEmpty { return task.meetingID == nil }
    let identities = names + ["Me", "自分", "私", "わたし"]
    return identities.map(normalized).filter { !$0.isEmpty }.contains(owner)
  }

  private static func normalized(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
  }
}
