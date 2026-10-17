import SwiftUI

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
