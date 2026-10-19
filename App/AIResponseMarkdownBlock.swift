import SwiftUI

// Typography/quote geometry adapted from ChatGPTMarkdownView (MIT), dc6e6a52.
// Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors.
// See Resources/ChatGPTUI-LICENSE.txt.
/// Chat-specific controls leave the editable summary's block renderer intact.
struct AIResponseMarkdownBlock: View {
  var block: MarkdownBlock

  var body: some View {
    switch block {
    case .code(let language, let text): AIResponseCodeBlock(language: language, code: text)
    case .table(let header, let rows): AIResponseTable(header: header, rows: rows)
    default: MarkdownBlockView(block: block)
    }
  }
}
