import Foundation

enum TaskBoardColumn: String, CaseIterable, Identifiable {
  case notStarted, inProgress, waiting, completed
  var id: Self { self }
  var title: String {
    switch self {
    case .notStarted: "着手前"
    case .inProgress: "進行中"
    case .waiting: "相手待ち"
    case .completed: "完了"
    }
  }
  func contains(_ task: MemoraTask) -> Bool {
    if task.isCompleted { return self == .completed }
    return switch self {
    case .notStarted: task.progress == .notStarted
    case .inProgress: task.progress == .inProgress
    case .waiting: task.progress == .waiting
    case .completed: false
    }
  }
  func applying(to task: MemoraTask) -> MemoraTask {
    var result = task
    result.isCompleted = self == .completed
    result.completedAt = result.isCompleted ? (task.completedAt ?? .now) : nil
    switch self {
    case .notStarted: result.progress = .notStarted
    case .inProgress: result.progress = .inProgress
    case .waiting: result.progress = .waiting
    case .completed: break
    }
    return result
  }
}
