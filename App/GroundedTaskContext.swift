import Foundation

/// Standalone task titles are auxiliary to records when both can answer a question.
enum GroundedTaskContext {
  static func render(_ tasks: [MemoraTask], matching words: [String], budget: Int) -> String {
    let header = "未完了のタスク:"
    guard budget > header.count + 3 else { return "" }
    let pending = tasks.filter { !$0.isCompleted && $0.meetingID == nil }
    let (related, other) = pending.reduce(into: ([MemoraTask](), [MemoraTask]())) { groups, task in
      if words.contains(where: { task.title.localizedCaseInsensitiveContains($0) }) {
        groups.0.append(task)
      } else {
        groups.1.append(task)
      }
    }
    var result = header
    var remaining = budget - header.count
    for task in related + other {
      let cost = task.title.count + 3
      guard cost <= remaining else { continue }
      result += "\n- " + task.title
      remaining -= cost
      if remaining <= 3 { break }
    }
    return result == header ? "" : result
  }
}
