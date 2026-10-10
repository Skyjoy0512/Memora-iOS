import Foundation

struct JournalDailyRecap {
  var heading: String
  var narrative: String
  var highlights: [String]
  var isFuture: Bool
  var items: [JournalRecapHighlight] = []

  var hasActivity: Bool { !isFuture && !highlights.isEmpty }
  var activitySummary: String { JournalRecapWriter.activitySummary(items: items) }

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
    let personalEntries = visibleEntries.filter { $0.meetingID == nil }
    var items: [JournalRecapHighlight] = visibleMeetings.map {
      JournalRecapHighlight(id: $0.id, date: $0.createdAt, kind: .record,
        title: $0.displayTitle, summary: JournalRecapWriter.excerpt($0.summaryPreview))
    }
    items += personalEntries.map {
      JournalRecapHighlight(id: $0.id, date: $0.occurredAt, kind: .init($0.kind),
        title: $0.title, summary: JournalRecapWriter.excerpt($0.summary))
    }
    items += completed.compactMap { task -> JournalRecapHighlight? in
      guard let completedAt = task.completedAt else { return nil }
      return JournalRecapHighlight(id: task.id, date: completedAt, kind: .completedTask,
        title: task.title, summary: "タスクを完了しました。")
    }
    items.sort {
      $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
    }
    let highlights = items.prefix(3).map(\.label)
    return JournalDailyRecap(heading: items.isEmpty ? heading : JournalRecapWriter.heading(items: items, isToday: isToday),
      narrative: items.isEmpty ? "この日の振り返りに使える記録はまだありません。記録が増えると、ここに1日の概要が表示されます。" : JournalRecapWriter.narrative(items: items, calendar: calendar),
      highlights: highlights, isFuture: false, items: items)
  }
}
