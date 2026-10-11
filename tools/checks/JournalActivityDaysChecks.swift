import Foundation

@main
struct JournalActivityDaysChecks {
  static func main() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let day = calendar.startOfDay(for: now)
    let earlier = calendar.date(byAdding: .day, value: -1, to: day)!
    let own = MemoraTask(id: UUID(), title: "自分", isCompleted: true, completedAt: now, ownedByMe: true)
    let other = MemoraTask(id: UUID(), title: "相手", isCompleted: true, completedAt: earlier, ownedByMe: false)
    let unknown = MemoraTask(id: UUID(), title: "日時不明", isCompleted: true, ownedByMe: true)
    let incomplete = MemoraTask(id: UUID(), title: "未完了", isCompleted: false, completedAt: earlier, ownedByMe: true)
    let tasks = [own, other, unknown, incomplete].filter { TaskOwnership.isMine($0, names: []) }
    let days = JournalActivityDays.build(recordedDays: [],
      completedAt: tasks.filter { $0.isCompleted }.compactMap(\.completedAt), now: now, calendar: calendar)
    precondition(days == [day])
    precondition(JournalActivityDays.build(recordedDays: [earlier], completedAt: [now, now], now: now, calendar: calendar) == [earlier, day])
    precondition(JournalActivityDays.build(recordedDays: [], completedAt: [now.addingTimeInterval(86_400)], now: now, calendar: calendar).isEmpty)
    var tokyo = calendar
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let late = day.addingTimeInterval(20 * 3_600)
    precondition(JournalActivityDays.build(recordedDays: [], completedAt: [late], now: late, calendar: tokyo) == [tokyo.startOfDay(for: late)])
    var waiting = MemoraTask(id: UUID(), title: "待ち", isCompleted: true, progress: .waiting)
    precondition(waiting.statusLabel == "完了")
    waiting.isCompleted = false
    precondition(waiting.statusLabel == "相手待ち")
    let restored = try JSONDecoder().decode(MemoraTask.self, from: JSONEncoder().encode(waiting))
    precondition(restored == waiting && restored.statusLabel == "相手待ち")
    print("Journal activity days and task status checks passed")
  }
}
