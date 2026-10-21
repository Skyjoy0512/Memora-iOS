import Foundation

@main
struct TaskContextLineChecks {
  static func main() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    precondition(TaskContextLine.text(progress: .notStarted, workDate: nil, isCompleted: false) == nil)
    precondition(TaskContextLine.text(progress: .waiting, workDate: nil, isCompleted: false) == "相手待ち")
    precondition(TaskContextLine.text(progress: .inProgress, workDate: nil, isCompleted: false) == "進行中")
    let planned = TaskContextLine.text(progress: .waiting, workDate: date, isCompleted: false)
    precondition(planned == "相手待ち · 取り組む日 \(MemoraFormat.dueDate(date))")
    precondition(TaskContextLine.text(progress: .notStarted, workDate: date, isCompleted: false) == "取り組む日 \(MemoraFormat.dueDate(date))")
    precondition(TaskContextLine.text(progress: .waiting, workDate: date, isCompleted: true) == nil)
    precondition(planned?.contains("期限") == false)
    print("TaskContextLineChecks: passed (quiet default, progress, planned work date, no due-date conflation, completed-state suppression)")
  }
}
