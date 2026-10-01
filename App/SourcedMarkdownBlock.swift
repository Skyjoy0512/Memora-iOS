import Foundation

/// A markdown block and the source lines it came from.
struct SourcedMarkdownBlock: Hashable {
  var block: MarkdownBlock
  var lines: Range<Int>
}
