import SwiftUI

/// The same block views remain mounted when the stream settles.
struct StreamingMarkdownView: View {
  var text: String
  var isStreaming: Bool
  @State private var cache = IncrementalMarkdownCache()

  var body: some View {
    let blocks = cache.blocks(for: text, isStreaming: isStreaming)
    VStack(alignment: .leading, spacing: MemoraTypography.paragraphSpacing) {
      ForEach(blocks.indices, id: \.self) { index in
        AIResponseMarkdownBlock(block: blocks[index])
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }
}
