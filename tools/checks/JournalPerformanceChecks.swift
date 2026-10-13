import Foundation

@main
struct JournalPerformanceChecks {
  static func main() {
    let names = ["山田 太郎", "TARO"]
    let tasks = (0..<1_000).map { number in
      MemoraTask(ownedByMe: number.isMultiple(of: 5) ? true : nil,
        assignee: number.isMultiple(of: 3) ? "ＴＡＲＯ" : number.isMultiple(of: 2) ? " 自分 " : "他人", meetingID: UUID())
    }
    precondition(TaskOwnership.ownedTasks(tasks, names: names) == tasks.filter { TaskOwnership.isMine($0, names: names) })
    measure("ownership-before", count: tasks.count) { tasks.filter { TaskOwnership.isMine($0, names: names) }.count }
    measure("ownership-batched", count: tasks.count) { TaskOwnership.ownedTasks(tasks, names: names).count }
    precondition(TaskOwnership.ownedTasks(tasks, names: ["他人"]).count != TaskOwnership.ownedTasks(tasks, names: names).count)
    print("JournalPerformanceChecks: passed (ownership and profile name changes)")
  }

  static func measure(_ name: String, count: Int, work: () -> Int) {
    var samples: [Double] = []
    for _ in 0..<21 {
      let start = ContinuousClock.now
      precondition(work() >= 0)
      let d = start.duration(to: .now).components
      samples.append(Double(d.seconds) * 1_000 + Double(d.attoseconds) / 1e15)
    }
    samples.sort()
    print(String(format: "%@,%d,median=%.3f,p95=%.3f,max=%.3f", name, count, samples[10], samples[19], samples[20]))
  }
}

struct MemoraTask: Equatable { var ownedByMe: Bool?; var assignee: String?; var meetingID: UUID? }
