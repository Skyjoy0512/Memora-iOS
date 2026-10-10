import Foundation

struct JournalRecapContext {
  var metrics: [String] = []
  var projects: [String] = []
  var people: [String] = []
  var decisions: [String] = []
  var openQuestions: [String] = []
  var places: [String] = []
  var nextSteps: [String] = []
  var healthFacts: [String] = []

  var cardMetrics: [String] {
    guard !healthFacts.isEmpty else { return Array(metrics.prefix(3)) }
    return Array(metrics.filter { !healthFacts.contains($0) }.prefix(2)) + Array(healthFacts.prefix(2))
  }

  var takeaway: String {
    guard let decision = decisions.first else { return "" }
    return "会議の記録では「\(JournalRecapWriter.excerpt(decision, limit: 60))」が決まりました。"
  }

  static func build(period: ReviewPeriod, meetings: [Meeting], completed: [MemoraTask],
                    entries: [LifeLogEntry], tasks: [MemoraTask], spaces: [MemoraSpace],
                    people: [Person], events: [JournalCalendarEvent], health: HealthReviewSnapshot?,
                    now: Date, calendar: Calendar) -> JournalRecapContext {
    var result = JournalRecapContext()
    if !meetings.isEmpty {
      let seconds = meetings.reduce(0) { total, meeting in
        total + (meeting.duration.isFinite ? max(0, meeting.duration) : 0)
      }
      let duration = durationText(seconds)
      result.metrics.append("会議・録音\(meetings.count)件" + (duration.isEmpty ? "" : "（\(duration)）"))
    }
    if !completed.isEmpty { result.metrics.append("タスク完了\(completed.count)件") }
    for kind in [LifeLogKind.memo, .photo] {
      let count = entries.filter { $0.kind == kind }.count
      if count > 0 { result.metrics.append("\(kind.label)\(count)件") }
    }
    result.decisions = unique(meetings.flatMap(\.decisions))
    result.openQuestions = unique(meetings.flatMap(\.openQuestions))
    let projectIDs = Set(meetings.compactMap(\.spaceID))
    result.projects = unique(spaces.filter { projectIDs.contains($0.id) }.map(\.name))
    let personIDs = Set(meetings.flatMap { $0.participantIDs ?? [] })
    result.people = unique(people.filter { personIDs.contains($0.id) }.map(\.name))
    result.places = unique(entries.compactMap { entry in
      if let name = entry.locationName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
      return entry.kind == .location ? entry.title : nil
    })
    if !result.places.isEmpty { result.metrics.append("場所の記録\(result.places.count)か所") }
    if let health {
      if let steps = health.steps, steps.isFinite, steps >= 0, steps < Double(Int.max) {
        result.healthFacts.append("歩数 \(Int(steps).formatted())歩")
      }
      if let seconds = health.sleepSeconds, !durationText(seconds).isEmpty {
        result.healthFacts.append("睡眠記録 \(durationText(seconds))")
      }
      if let seconds = health.workoutSeconds, !durationText(seconds).isEmpty {
        result.healthFacts.append("ワークアウト \(durationText(seconds))")
      }
      result.metrics += result.healthFacts
    }
    if period.contains(now), let tomorrow = calendar.date(byAdding: .day, value: 1, to: period.start) {
      let due = tasks.filter {
        !$0.isCompleted && !SampleContent.isSample(task: $0)
          && $0.dueDate.map { calendar.isDate($0, inSameDayAs: tomorrow) } == true
      }.sorted {
        if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        return $0.id.uuidString < $1.id.uuidString
      }
      result.nextSteps = unique(due.map { "明日が期限：\($0.title)（現在未完了）" })
      let upcoming = events.filter { period.contains($0.start) && $0.start > now }
        .sorted { $0.start < $1.start }
      result.nextSteps += unique(upcoming.map { "この後の予定：\($0.start.formatted(date: .omitted, time: .shortened)) \($0.title)" })
    }
    return result
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.compactMap { value in
      let text = JournalRecapWriter.excerpt(value)
      guard !text.isEmpty, seen.insert(text).inserted else { return nil }
      return text
    }
  }

  private static func durationText(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0, seconds < Double(Int.max) else { return "" }
    let minutes = Int(seconds / 60)
    if minutes == 0 { return "1分未満" }
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(minutes)分" }
    return "\(hours)時間" + (remainder == 0 ? "" : "\(remainder)分")
  }
}
