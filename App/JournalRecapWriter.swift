import Foundation

enum JournalRecapWriter {
  static func heading(items: [JournalRecapHighlight], isToday: Bool) -> String {
    if items.count == 1, let item = items.first {
      let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !title.isEmpty, title.count <= 24 {
        switch item.kind {
        case .completedTask: return "「\(title)」を完了"
        case .memo, .photo, .record: return "「\(title)」の記録"
        case .event: return "「\(title)」の予定"
        case .location: break
        }
      }
    }
    let kinds = Set(items.map(\.kind))
    if kinds == [.completedTask] {
      return items.count == 1 ? "ひとつのタスクを完了" : "\(items.count)件のタスクを完了"
    }
    if kinds == [.record] { return "会議・録音を残した1日" }
    if kinds == [.memo] { return "言葉で残した1日" }
    if kinds == [.photo] { return "写真で残した1日" }
    if kinds == [.memo, .photo] { return "言葉と写真で残した1日" }
    if kinds == [.location] { return "場所の記録を振り返る" }
    if kinds == [.event] { return "登録した予定を振り返る" }
    return isToday ? "今日の記録をつなぐ" : "記録を重ねた1日"
  }

  static func narrative(items: [JournalRecapHighlight], calendar: Calendar) -> String {
    let windows = [(0..<6, "深夜・早朝"), (6..<12, "午前"), (12..<18, "午後"), (18..<24, "夜")]
    return windows.compactMap { hours, label -> String? in
      let records = items.filter { hours.contains(calendar.component(.hour, from: $0.date)) }
      guard !records.isEmpty else { return nil }
      return representativeItems(records, limit: 2).enumerated().map { index, item in
        let introduction = index == 0 ? "\(label)は、" : "また、"
        let description = introduction + sentence(for: item)
        guard !item.summary.isEmpty, item.kind != .completedTask else { return description }
        return description + "記録には「\(excerpt(item.summary, limit: 100))」とあります。"
      }.joined(separator: "")
    }.joined(separator: "\n\n")
  }

  static func activitySummary(items: [JournalRecapHighlight]) -> String {
    let counts = Dictionary(grouping: items, by: \.kind)
    return JournalRecapHighlight.Kind.allCases.compactMap { kind -> String? in
      guard let count = counts[kind]?.count, count > 0 else { return nil }
      let label: String
      switch kind {
      case .completedTask: label = "完了タスク"
      case .event: label = "登録した予定"
      case .location: label = "場所の記録"
      default: label = kind.label
      }
      return "\(label)\(count)件"
    }.joined(separator: " · ")
  }

  static func cardPreview(items: [JournalRecapHighlight], calendar: Calendar) -> String {
    let windows = [(0..<6, "深夜・早朝"), (6..<12, "午前"), (12..<18, "午後"), (18..<24, "夜")]
    let moments: [(String, JournalRecapHighlight)] = windows.compactMap { hours, label in
      let records = items.filter { hours.contains(calendar.component(.hour, from: $0.date)) }
      guard let item = representativeItems(records, limit: 1).first else { return nil }
      return (label, item)
    }
    if items.count == 1, let (time, item) = moments.first, !item.summary.isEmpty,
       item.kind == .memo || item.kind == .record || item.kind == .photo {
      return "\(time)の記録には「\(excerpt(item.summary, limit: 90))」とあります。"
    }
    if moments.count <= 1 {
      return narrative(items: items, calendar: calendar).replacingOccurrences(of: "\n\n", with: " ")
    }
    return moments.map { time, item in
      var concise = item
      if concise.title.count > 18 { concise.title = String(concise.title.prefix(18)) + "…" }
      return "\(time)は、" + sentence(for: concise)
    }.joined(separator: " ")
  }

  static func excerpt(_ source: String, limit: Int = 300) -> String {
    let overview = MarkdownBlockParser.overview(of: source)
    let plain = overview.isEmpty ? MarkdownBlockParser.plainText(source) : overview
    let compact = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return compact.count > limit ? String(compact.prefix(limit)) + "…" : compact
  }

  private static func representativeItems(_ items: [JournalRecapHighlight], limit: Int) -> [JournalRecapHighlight] {
    items.sorted {
      let first = $0.priority + ($0.kind == .completedTask ? 2 : !$0.summary.isEmpty && $0.kind != .location && $0.kind != .event ? 1 : 0)
      let second = $1.priority + ($1.kind == .completedTask ? 2 : !$1.summary.isEmpty && $1.kind != .location && $1.kind != .event ? 1 : 0)
      if first != second { return first > second }
      if $0.date != $1.date { return $0.date < $1.date }
      return $0.id.uuidString < $1.id.uuidString
    }.prefix(limit).sorted { $0.date < $1.date }
  }

  private static func sentence(for item: JournalRecapHighlight) -> String {
    let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let subject = title.isEmpty ? "無題の\(item.category)" : title
    switch item.kind {
    case .completedTask: return "「\(subject)」を完了しました。"
    case .record: return "「\(subject)」の会議・録音を残しました。"
    case .memo: return "「\(subject)」を書き残しました。"
    case .photo: return "「\(subject)」の写真を残しました。"
    case .location: return "「\(subject)」の場所の記録があります。"
    case .event: return "「\(subject)」の予定が登録されています。"
    }
  }
}
