import Foundation

@main
struct ProjectTaskListChecks {
  static func main() {
    let first = UUID(), second = UUID(), moved = UUID()
    let own = MemoraTask(id: UUID(), title: "自分の担当", meetingID: first, isCompleted: false, ownedByMe: true)
    let other = MemoraTask(id: UUID(), title: "別の担当", meetingID: first, assignee: "田中", isCompleted: false, ownedByMe: false)
    let unknownOwner = MemoraTask(id: UUID(), title: "担当未定", meetingID: second, isCompleted: false)
    let completed = MemoraTask(id: UUID(), title: "完了済み", meetingID: second, isCompleted: true)
    let outside = MemoraTask(id: UUID(), title: "別プロジェクト", meetingID: moved, isCompleted: false, ownedByMe: true)
    let global = MemoraTask(id: UUID(), title: "全体の自分のタスク", isCompleted: false, ownedByMe: true)
    let inputs = [global, own, outside, other, completed, unknownOwner]
    let records: Set<UUID> = [first, second]
    precondition(ProjectTaskList.select(from: inputs, recordIDs: records) == [own, other, unknownOwner])
    precondition(ProjectTaskList.select(from: inputs, recordIDs: records, includeCompleted: true) == [own, other, completed, unknownOwner])
    precondition(ProjectTaskList.select(from: inputs, recordIDs: []).isEmpty)
    precondition(ProjectTaskList.select(from: inputs, recordIDs: [second]) == [unknownOwner])
    precondition(ProjectTaskList.select(from: inputs, recordIDs: [first, second, moved]).contains(outside))
    var reassigned = other
    reassigned.meetingID = moved
    precondition(ProjectTaskList.select(from: [own, reassigned], recordIDs: records) == [own])
    var done = own
    done.isCompleted = true
    precondition(ProjectTaskList.select(from: [done], recordIDs: records).isEmpty)
    precondition(ProjectTaskList.select(from: [done], recordIDs: records, includeCompleted: true) == [done])
    print("ProjectTaskListChecks: passed (all assignees, completion, current membership/move/removal, no global/orphan fallback; local fixture)")
  }
}
