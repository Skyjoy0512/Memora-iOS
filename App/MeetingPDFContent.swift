import Foundation

// Keeps the meeting export's existing sections and task order, separate from the screen layout.
struct MeetingPDFContent: Sendable {
  var title: String
  var metadata: String
  var summary: String
  var decisions: [String]
  var actions: [String]
  var openQuestions: [String]
  var keyPoints: [String]

  func input() throws -> DocumentPDFRenderer.Input {
    try Task.checkCancellation()
    var blocks: [MarkdownBlock] = []
    if !summary.isEmpty {
      blocks.append(.heading(level: 2, text: "要約"))
      if MarkdownBlockParser.hasBlockStructure(summary) {
        blocks += MarkdownBlockParser.blocks(for: summary)
      } else {
        blocks.append(.paragraph(summary))
      }
    }
    for (title, items) in [("補足の決定事項", SummaryContentProjection.supplements(decisions, markdown: summary)), ("タスク（現在の状態）", actions),
                           ("補足の未決事項", SummaryContentProjection.supplements(openQuestions, markdown: summary)),
                           ("補足の要点", SummaryContentProjection.supplements(keyPoints, markdown: summary))] where !items.isEmpty {
      try Task.checkCancellation()
      blocks.append(.heading(level: 2, text: title))
      blocks += items.map { .bullet(level: 0, marker: .dot, text: $0) }
    }
    return DocumentPDFRenderer.Input(title: title, date: metadata, markdown: "", blocks: blocks)
  }
}
