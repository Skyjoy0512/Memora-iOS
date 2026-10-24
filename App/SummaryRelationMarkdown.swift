import Foundation

enum SummaryRelationMarkdown {
  static func bullets(_ items: [String], relations: [SummaryRelation], target: SummaryRelation.Target = .decision,
                      level: Int = 0, prefix: String = "") -> [String] {
    groups(items, relations: relations, target: target, level: level, prefix: prefix).flatMap { $0 }
  }

  /// A parent and its qualifiers must stay together when model input is split.
  static func groups(_ items: [String], relations: [SummaryRelation], target: SummaryRelation.Target = .decision,
                     level: Int = 0, prefix: String = "") -> [[String]] {
    let indent = String(repeating: "  ", count: max(0, level))
    var byParent: [String: [SummaryRelation]] = [:]
    var seen: Set<SummaryRelation> = []
    for relation in relations where relation.target == target && seen.insert(relation).inserted {
      byParent[relation.parent, default: []].append(relation)
    }
    var groups: [[String]] = []
    for item in items {
      var lines = [indent + "- " + prefix + item]
      for relation in byParent[item] ?? [] {
        let child = relation.kind.label + "：「" + inlineLiteral(relation.quote) + "」"
        lines.append(indent + "  - " + child)
      }
      groups.append(lines)
    }
    return groups
  }

  /// A complete parent and its qualifiers enter the context together, or not at
  /// all. Trimming the quote here could drop the very condition it protects.
  static func overviewNotes(_ topics: [SummaryTopic], limit: Int) -> String {
    var notes = ""
    for (index, topic) in topics.enumerated() {
      let lines = bullets(Array(topic.points.prefix(2)), relations: topic.relations, target: .point)
        + bullets(Array(topic.decisions.prefix(2)), relations: topic.relations, prefix: "（決定）")
      let block = "\(index + 1). \(topic.title)\n" + lines.joined(separator: "\n") + "\n"
      guard notes.count + block.count <= limit else { break }
      notes += block
    }
    return notes
  }

  private static func inlineLiteral(_ text: String) -> String {
    text.map { "\\[]*_`<>!|#~".contains($0) ? "\\" + String($0) : String($0) }.joined()
  }
}
