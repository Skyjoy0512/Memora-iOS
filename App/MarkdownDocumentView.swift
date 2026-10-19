import SwiftUI

/// Draws a structured markdown document — headings, nested lists, quotes,
/// rules and tables — for generated summaries. A table's rows become compact
/// cards, since five columns do not fit an iPhone's width.
struct MarkdownDocumentView: View {
  var markdown: String
  /// On screen, only the blocks scrolled into view are built, so a long
  /// summary does not lay out every paragraph at once. Rendering to a PDF
  /// needs every block, so it stays eager there.
  var isLazy = false

  var body: some View {
    let blocks = MarkdownBlockParser.blocks(for: markdown)

    Group {
      if isLazy {
        LazyVStack(alignment: .leading, spacing: MarkdownBlockView.blockSpacing) {
          rows(blocks)
        }
      } else {
        VStack(alignment: .leading, spacing: MarkdownBlockView.blockSpacing) {
          rows(blocks)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }

  private func rows(_ blocks: [MarkdownBlock]) -> some View {
    ForEach(blocks.indices, id: \.self) { index in
      MarkdownBlockView(block: blocks[index])
    }
  }
}
