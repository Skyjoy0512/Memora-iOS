import Foundation

/// A view-local derived cache; it owns no user state and publishes no invalidations.
@MainActor
final class IncrementalMarkdownCache {
  private var document = IncrementalMarkdown()

  func blocks(for text: String, isStreaming: Bool) -> [MarkdownBlock] {
    document.update(text, isStreaming: isStreaming)
    return document.blocks
  }
}
