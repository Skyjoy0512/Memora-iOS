import Foundation

struct ReviewStatistics {
  var period: ReviewPeriod
  var meetingCount: Int
  var meetingSeconds: TimeInterval
  var completedTaskCount: Int
  var dueTaskCount: Int
  var waitingTaskCount: Int
  var memoCount: Int
  var photoCount: Int
  var eventCount: Int
  var locationCount: Int

  static func build(period: ReviewPeriod, meetings: [Meeting], tasks: [MemoraTask], entries: [LifeLogEntry]) -> ReviewStatistics {
    let records = meetings.filter { period.contains($0.createdAt) && !SampleContent.isSample(meetingID: $0.id) }
    let realTasks = tasks.filter { !SampleContent.isSample(task: $0) }
    let journal = entries.filter { period.contains($0.occurredAt) && !SampleContent.isSample(lifeLogEntry: $0) }
    return ReviewStatistics(
      period: period,
      meetingCount: records.count,
      meetingSeconds: records.reduce(0) { $0 + max(0, $1.duration) },
      completedTaskCount: realTasks.filter { $0.isCompleted && $0.completedAt.map(period.contains) == true }.count,
      dueTaskCount: realTasks.filter { !$0.isCompleted && $0.dueDate.map(period.contains) == true }.count,
      waitingTaskCount: realTasks.filter { !$0.isCompleted && $0.progress == .waiting }.count,
      memoCount: journal.filter { $0.kind == .memo }.count,
      photoCount: journal.filter { $0.kind == .photo }.count,
      eventCount: journal.filter { $0.kind == .event }.count,
      locationCount: journal.filter { $0.kind == .location }.count
    )
  }

  func markdown(includesLocation: Bool) -> String {
    var lines = [
      "対象期間: **\(period.label)**",
      "## 仕事と行動",
      "- 会議・録音: **\(meetingCount)件**（\(MemoraFormat.duration(meetingSeconds))）",
      "- 期間内に完了したタスク: **\(completedTaskCount)件**",
      "- 期間内が期限の未完了タスク: **\(dueTaskCount)件**",
      "- 相手待ち: **\(waitingTaskCount)件**（現在の状態。期間内の履歴ではありません）",
      "",
      "## ジャーナル",
      "- メモ: \(memoCount)件 / 写真: \(photoCount)件",
      "- 登録されたイベント: \(eventCount)件（実施を確認した件数ではありません）"
    ]
    if includesLocation { lines.append("- 検出・記録された場所: \(locationCount)件（全移動を示すものではありません）") }
    lines.append("\n端末に保存された記録の全件集計です。未記録の活動は含みません。完了日時のない旧タスクは完了件数に含みません。")
    return lines.joined(separator: "\n")
  }
}
