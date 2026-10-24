import Foundation

/// Prepare every topic before requesting any template generation. An oversized
/// parent/qualifier group fails as a whole, never as an unqualified assertion.
struct SummaryTemplateNotes {
  var title: String
  var chunks: [String]

  static func prepare(_ topics: [SummaryTopic], characterLimit: Int) -> [Self]? {
    guard characterLimit > 0 else { return nil }
    var prepared: [Self] = []
    for topic in topics {
      let groups = SummaryRelationMarkdown.groups(topic.points, relations: topic.relations, target: .point)
        + SummaryRelationMarkdown.groups(topic.decisions, relations: topic.relations)
      let notes = groups.map { $0.joined(separator: "\n") }
        + topic.concerns + topic.questions
        + topic.actions.map { "\($0.title) / 担当: \($0.owner ?? "未定") / 期限: \($0.due ?? "未定")" }
      var chunks: [String] = []
      var chunk = ""
      for note in notes {
        let block = note + "\n"
        guard block.count <= characterLimit else { return nil }
        if chunk.count + block.count > characterLimit {
          chunks.append(chunk)
          chunk = ""
        }
        chunk += block
      }
      if !chunk.isEmpty { chunks.append(chunk) }
      prepared.append(Self(title: topic.title, chunks: chunks))
    }
    return prepared
  }
}
