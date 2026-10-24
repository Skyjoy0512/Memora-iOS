import Foundation

/// A bounded visual excerpt, not a second AI interpretation of the meeting.
struct MeetingSummaryPosterContent: Equatable {
  var title: String
  var date: String
  var overview: String
  var decisions: [String]
  var actions: [String]
  var questions: [String]
  var fullSummary: String

  init(title: String, date: String, summary: String) {
    self.title = Self.excerpt(title, limit: 64)
    self.date = date
    fullSummary = summary
    let extracted = MarkdownSummaryExtractor.extract(from: summary)
    let passage = MarkdownBlockParser.overview(of: summary)
    overview = Self.excerpt(passage.isEmpty ? Self.labelledOverview(summary) : passage, limit: 160)
    decisions = extracted.decisions.prefix(2).map { Self.excerpt($0, limit: 72) }
    actions = extracted.actions.prefix(2).map { action in
      let fields = [action.title, action.detail.isEmpty ? nil : action.detail,
                    action.owner.map { "担当：" + $0 }, action.due.map { "期限：" + $0 }]
      return Self.excerpt(fields.compactMap { $0 }.joined(separator: " ／ "), limit: 90)
    }
    questions = extracted.openQuestions.prefix(2).map { Self.excerpt($0, limit: 80) }
  }

  static func excerpt(_ text: String, limit: Int) -> String {
    let plain = MarkdownBlockParser.plainText(text)
    return plain.count > limit ? String(plain.prefix(limit - 1)) + "…" : plain
  }

  private static func labelledOverview(_ summary: String) -> String {
    // Older summaries used a bullet for 用件 instead of an overview paragraph.
    var firstPassage = ""
    for block in MarkdownBlockParser.blocks(for: summary) {
      let text: String
      switch block {
      case .bullet(_, _, let value), .paragraph(let value): text = value
      default: continue
      }
      if firstPassage.isEmpty {
        let plain = MarkdownBlockParser.plainText(text)
        if plain.count >= 20 { firstPassage = plain }
      }
      for line in text.components(separatedBy: "\n") {
        let plain = MarkdownBlockParser.plainText(line)
        for label in ["会議の概要:", "会議の概要：", "概要:", "概要：", "用件:", "用件："] {
          if let range = plain.range(of: label), plain[..<range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
            let passage = String(plain[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !passage.isEmpty { return passage }
          }
        }
      }
    }
    // Unknown labels cannot grant a semantic interpretation. Show the literal
    // passage as an excerpt rather than saying that a populated summary is empty.
    return firstPassage
  }
}
