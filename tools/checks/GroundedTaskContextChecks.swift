import Foundation

@main
enum GroundedTaskContextChecks {
  static func main() {
    let noise = (0..<200).map { index in
      MemoraTask(id: UUID(), title: "定例作業 \(index)", isCompleted: false)
    }
    let relevant = MemoraTask(id: UUID(), title: "カモメ設計の判断を確認", isCompleted: false)
    let denied = [
      MemoraTask(id: UUID(), title: "カモメ設計完了済み", isCompleted: true),
      MemoraTask(id: UUID(), title: "カモメ設計の記録内タスク", meetingID: UUID(), isCompleted: false)
    ]
    let section = GroundedTaskContext.render(noise + denied + [relevant], matching: ["カモメ設計"], budget: 50)
    precondition(section.count <= 50 && section.hasPrefix("未完了のタスク:\n- カモメ設計の判断を確認"))
    precondition(!section.contains("完了済み") && !section.contains("記録内タスク"))
    let title = String(repeating: "👩‍💻", count: 1_000)
    let large = MemoraTask(id: UUID(), title: title, isCompleted: false)
    let separate = GroundedTaskContext.render([large, relevant], matching: [], budget: 40)
    precondition(separate.hasSuffix(relevant.title) && !separate.contains("👩‍💻"))
    precondition(GroundedTaskContext.render([relevant], matching: [], budget: 0).isEmpty)
    precondition(GroundedTaskContext.render(denied, matching: [], budget: 50).isEmpty)
    print("GroundedTaskContextChecks: passed (complete titles, priority, budget, standalone scope)")
  }
}
