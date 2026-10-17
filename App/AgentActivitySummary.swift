import Foundation

/// Derived from recorded tool events only; model reasoning is never an input.
struct AgentActivitySummary: Equatable {
  var total: Int
  var failed: Int
  var declined: Int
  var isRunning: Bool
  var isWaiting: Bool

  init(steps: [AgentStep], isRunning: Bool, isWaiting: Bool) {
    total = steps.count
    failed = steps.filter { $0.state == .failed }.count
    declined = steps.filter { $0.state == .declined }.count
    self.isRunning = isRunning
    self.isWaiting = isRunning && isWaiting
  }

  var label: String {
    if isWaiting { return "確認待ち · 操作\(total)件" }
    if isRunning { return "実行状況 · 操作\(total)件" }
    if failed > 0 { return "実行結果 · 失敗\(failed)件" }
    if declined > 0 { return "実行結果 · 実行せず\(declined)件" }
    return "実行結果 · 操作\(total)件"
  }
}
