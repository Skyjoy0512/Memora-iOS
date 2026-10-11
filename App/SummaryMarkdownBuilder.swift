import Foundation

/// Lays out on-device topic notes as the same documents the cloud writes, one
/// layout per template, so a summary reads alike whichever engine made it.
enum SummaryMarkdownBuilder {
  static func build(
    template: SummaryTemplateChoice,
    input: MeetingSummaryInput,
    headline: String,
    overview: String,
    topics: [SummaryTopic]
  ) -> String {
    let orderedTopics: [SummaryTopic]
    if input.preferences.displayOrder == .importance, template != .builtIn(.detailedMinutes) {
      orderedTopics = topics.enumerated().sorted { first, second in
        let firstPriority = first.element.decisions.count + first.element.actions.count
        let secondPriority = second.element.decisions.count + second.element.actions.count
        return firstPriority == secondPriority ? first.offset < second.offset : firstPriority > secondPriority
      }.map(\.element)
    } else {
      orderedTopics = topics.sorted { $0.startTime < $1.startTime }
    }
    let speakers = input.speakers.isEmpty ? "不明" : input.speakers.joined(separator: ", ")
    let decisions = unique(topics.flatMap(\.decisions))
    let questions = unique(topics.flatMap(\.questions))
    let actions = SummaryResponseParser.deduplicated(topics.flatMap(\.actions))

    var lines: [String] = []
    switch template {
    case .builtIn(.detailedOverview):
      lines = [
        "# \(headline)",
        "**日時**: \(input.dateText)  ",
        "**参加者**: \(speakers)  ",
        "**会議の概要**:  ",
        overview
      ]
      for (index, topic) in orderedTopics.enumerated() {
        lines += ["", "---", "## トピック\(index + 1)：\(topic.title)", "### サマリー"]
        if !topic.speakers.isEmpty {
          lines.append("- **関与者**: \(topic.speakers.joined(separator: ", "))")
        }
        lines.append("- **要点**:")
        lines += topic.points.map { "  - \($0)" }
        lines.append("- **決定事項**:")
        lines += nested(topic.decisions)
        lines.append("- **課題・懸念**:")
        lines += nested(topic.concerns)
        lines.append("### アクションアイテム")
        lines += actionTable(topic.actions)
        lines.append("### オープンクエスチョン")
        lines += bullets(topic.questions)
      }

    case .builtIn(.meetingMinutes), .market:
      lines = [
        "## 会議情報",
        "> 日時: \(input.dateText)",
        "> 参加者: \(speakers)",
        "## 概要",
        overview,
        "## 議事録"
      ]
      for topic in orderedTopics {
        lines.append("### \(topic.title)")
        lines += topic.points.map { "- \($0)" }
      }
      lines.append("## 決定事項")
      lines += bullets(decisions)
      lines.append("## 今後の予定・アクション項目")
      lines += actions.isEmpty
        ? ["- なし"]
        : actions.map { "- [ ] \($0.title)（担当: \($0.owner ?? "未定") / 期限: \($0.due ?? "未定")）" }
      lines.append("## 未決事項")
      lines += bullets(questions)

    case .builtIn(.detailedMinutes):
      lines = ["## 会議の要旨", overview, "## 主要な決定事項"]
      lines += bullets(decisions)
      lines.append("## アクションアイテム")
      lines += actions.isEmpty
        ? ["- なし"]
        : actions.map { "- @\($0.owner ?? "未定") - \($0.title) - 期限: \($0.due ?? "未定")" }
      lines.append("## 詳細議事録")
      for topic in orderedTopics {
        let range = "\(MemoraFormat.duration(topic.startTime))-\(MemoraFormat.duration(topic.endTime))"
        lines.append("### [\(range)] \(topic.title)")
        lines += topic.points.map { "- \($0)" }
      }
      lines.append("## 未決事項")
      lines += bullets(questions)

    case .builtIn(.actionPlan):
      lines = [
        "# \(headline)",
        "**日時**: \(input.dateText)  ",
        "**概要**: \(overview)",
        "## アクションアイテム"
      ]
      lines += actionTable(actions)
      lines.append("## 決定事項")
      lines += bullets(decisions)
      lines.append("## 未決事項・確認が必要なこと")
      lines += bullets(questions)
    }
    return lines.joined(separator: "\n")
  }

  private static func bullets(_ items: [String]) -> [String] {
    items.isEmpty ? ["- なし"] : items.map { "- \($0)" }
  }

  private static func nested(_ items: [String]) -> [String] {
    items.isEmpty ? ["  - なし"] : items.map { "  - \($0)" }
  }

  private static func actionTable(_ actions: [SummaryActionItem]) -> [String] {
    guard !actions.isEmpty else { return ["なし"] }
    return [
      "| タイトル | 説明 | 責任者 | 期限 | 備考 |",
      "|:---|:---|:---|:---|:---|"
    ] + actions.map { action in
      "| \(cell(action.title)) | \(cell(action.detail)) | \(cell(action.owner ?? "未定")) | \(cell(action.due ?? "未定")) | |"
    }
  }

  /// A pipe inside a cell would split the row.
  private static func cell(_ text: String) -> String {
    text.replacingOccurrences(of: "|", with: "／").replacingOccurrences(of: "\n", with: " ")
  }

  private static func unique(_ items: [String]) -> [String] {
    var seen: Set<String> = []
    return items.filter { seen.insert(SummaryResponseParser.taskKey($0)).inserted }
  }
}
