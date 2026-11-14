import Foundation

/// Composes already-extracted facts without inventing content for a profile.
/// Semantic extraction stays in the engines; this layer only arranges facts.
enum SummaryMarkdownBuilder {
  static func build(template: SummaryTemplateChoice, input: MeetingSummaryInput,
                    headline: String, overview: String, topics: [SummaryTopic]) -> String {
    let ordered: [SummaryTopic]
    if input.preferences.displayOrder == .importance, template != .builtIn(.detailedMinutes) {
      ordered = topics.enumerated().sorted {
        let left = $0.element.decisions.count + $0.element.actions.count
        let right = $1.element.decisions.count + $1.element.actions.count
        return left == right ? $0.offset < $1.offset : left > right
      }.map(\.element)
    } else {
      ordered = topics.sorted { $0.startTime < $1.startTime }
    }
    let decisions = unique(topics.flatMap(\.decisions))
    let questions = unique(topics.flatMap(\.questions))
    let includesActions: Bool = if case .market(let market) = template { market.includesActions } else { true }
    let actions = includesActions ? SummaryResponseParser.deduplicated(topics.flatMap(\.actions)) : []
    let reserved = Set((decisions + questions + actions.map(\.title)).map(SummaryResponseParser.taskKey))
    var seen = reserved
    if !overview.isEmpty { seen.insert(SummaryResponseParser.taskKey(overview)) }
    var lines = ["# \(headline)"]
    if !overview.isEmpty { lines += ["", overview] }
    for topic in ordered {
      let points = unique(topic.points + topic.concerns).filter { point in
        (!overview.contains(point) && seen.insert(SummaryResponseParser.taskKey(point)).inserted) || topic.relations.contains { $0.target == .point && $0.parent == point }
      }
      guard !points.isEmpty else { continue }
      let location = template == .builtIn(.detailedMinutes) && input.duration > 0
        ? "[\(MemoraFormat.duration(topic.startTime))-\(MemoraFormat.duration(topic.endTime))] " : ""
      lines += ["", "## \(location)\(topic.title)"]
      lines += SummaryRelationMarkdown.bullets(points, relations: topic.relations, target: .point)
    }
    let relations = topics.flatMap(\.relations)
    if !decisions.isEmpty {
      lines += ["", "## 決定事項"] + SummaryRelationMarkdown.bullets(decisions, relations: relations)
    }
    if !actions.isEmpty {
      lines += ["", "## 次のアクション"]
      for action in actions {
        var metadata: [String] = []
        if let owner = SummaryActionItem.normalized(action.owner) { metadata.append("担当: " + owner) }
        if let due = SummaryActionItem.normalized(action.due) { metadata.append("期限: " + due) }
        let suffix = metadata.isEmpty ? "" : "（" + metadata.joined(separator: " / ") + "）"
        lines.append("- [ ] \(action.title)\(suffix)")
        if !action.detail.isEmpty, action.detail != action.title { lines.append("  " + action.detail) }
      }
    }
    if !questions.isEmpty { lines += ["", "## 未解決の問い"] + questions.map { "- " + $0 } }
    return SummaryResponseParser.generatedMarkdown(lines.joined(separator: "\n"))
  }

  private static func unique(_ items: [String]) -> [String] {
    var seen = Set<String>()
    return items.filter { SummaryActionItem.normalized($0) != nil && seen.insert(SummaryResponseParser.taskKey($0)).inserted }
  }
}
