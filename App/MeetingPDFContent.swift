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
    for (title, items) in [("決まったこと", decisions), ("次の行動", actions),
                           ("まだ決まっていないこと", openQuestions), ("重要なポイント", keyPoints)] where !items.isEmpty {
      try Task.checkCancellation()
      blocks.append(.heading(level: 2, text: title))
      blocks += items.map { .bullet(level: 0, marker: .dot, text: $0) }
    }
    return DocumentPDFRenderer.Input(title: title, date: metadata, markdown: "", blocks: blocks)
  }
}
