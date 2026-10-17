import SwiftUI

// Typography/quote geometry adapted from ChatGPTMarkdownView (MIT), dc6e6a52.
// Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors.
// See Resources/ChatGPTUI-LICENSE.txt.
/// Chat-specific controls leave the editable summary's block renderer intact.
struct AIResponseMarkdownBlock: View {
  var block: MarkdownBlock

  @ScaledMetric(relativeTo: .body) private var readingLineSpacing: CGFloat = 5

  var body: some View {
    switch block {
    case .code(let language, let text): AIResponseCodeBlock(language: language, code: text)
    case .table(let header, let rows): AIResponseTable(header: header, rows: rows)
    case .paragraph(let text):
      MarkdownBlockView.inline(text).font(.body).lineSpacing(readingLineSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .quote(let text):
      MarkdownBlockView.inline(text).font(.body).lineSpacing(readingLineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 17)
        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.25)).frame(width: 4) }
    default: MarkdownBlockView(block: block)
    }
  }
}
