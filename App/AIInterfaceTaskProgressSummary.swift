import Foundation

/// Completion counts for the TaskProgress component.
///
/// Every number is derived from the authorized tasks the model passed, never
/// from the display JSON: the interface carries no value, so a count or a
/// percentage can never be invented. The design borrows the headline-number
/// idea from OpenUI's `MetricIndicator` (MIT, 8d9c4c3b) as an independent
/// Swift implementation.
struct AIInterfaceTaskProgressSummary: Equatable {
  var total: Int
  var completed: Int

  var remaining: Int { max(0, total - completed) }
  var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
  var isComplete: Bool { total > 0 && completed == total }

  var accessibilityValue: String { "\(total)件中\(completed)件が完了" }

  init(tasks: [MemoraTask]) {
    total = tasks.count
    completed = tasks.filter(\.isCompleted).count
  }
}
