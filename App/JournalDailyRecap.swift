import Foundation

struct JournalDailyRecap {
  var heading: String
  var narrative: String
  var highlights: [String]
  var isFuture: Bool

  var hasActivity: Bool { !isFuture && !highlights.isEmpty }

  static func build(date: Date, meetings: [Meeting], tasks: [MemoraTask],
                    entries: [LifeLogEntry], now: Date = .now,
                    calendar: Calendar = .current) -> JournalDailyRecap {
    let period = ReviewPeriod.day(date, calendar: calendar)
    let isFuture = period.start > now
    let isToday = period.contains(now)
    let heading = isFuture ? "この日の予定" : isToday ? "今日はここまで" : "こんな1日でした"
    guard !isFuture else {
      return JournalDailyRecap(heading: heading,
        narrative: "まだ先の日です。登録した予定や記録は下のタイムラインで確認できます。",
        highlights: [], isFuture: true)
    }
    let visibleMeetings = meetings.filter {
      period.contains($0.createdAt) && $0.createdAt <= now && !SampleContent.isSample(meetingID: $0.id)
    }
    let visibleEntries = entries.filter {
      period.contains($0.occurredAt) && $0.occurredAt <= now && !SampleContent.isSample(lifeLogEntry: $0)
    }
    let completed = tasks.filter {
      !SampleContent.isSample(task: $0) && $0.isCompleted
        && $0.completedAt.map { period.contains($0) && $0 <= now } == true
    }
    var sentences: [String] = []
    if !visibleMeetings.isEmpty {
      sentences.append("会議・録音が\(visibleMeetings.count)件残っています。")
    }
    if !completed.isEmpty {
      sentences.append("タスクを\(completed.count)件完了しました。")
    }
    let personalEntries = visibleEntries.filter { $0.meetingID == nil }
    let notes = personalEntries.filter { $0.kind == .memo || $0.kind == .photo }
    if !notes.isEmpty { sentences.append("メモや写真を\(notes.count)件残しました。") }
    let places = personalEntries.filter { $0.kind == .location }
    if !places.isEmpty { sentences.append("場所の記録が\(places.count)件あります。") }
    let events = personalEntries.filter { $0.kind == .event }
    if !events.isEmpty { sentences.append("登録したイベントが\(events.count)件あります。") }
    let highlights = (
      visibleMeetings.map { ($0.createdAt, "会議・録音：\($0.displayTitle)") }
      + personalEntries.map { ($0.occurredAt, "\($0.kind.label)：\($0.title)") }
      + completed.compactMap { task in task.completedAt.map { ($0, "完了：\(task.title)") } }
    ).sorted { $0.0 < $1.0 }.prefix(3).map { $0.1 }
    return JournalDailyRecap(heading: heading,
      narrative: sentences.isEmpty ? "この日の振り返りに使える記録はまだありません。記録が増えると、ここに1日の概要が表示されます。" : sentences.joined(separator: "\n\n"),
      highlights: highlights, isFuture: false)
  }
}
