import Foundation

/// Presentation-only deduplication uses whole readable blocks. A substring
/// such as 公開 inside 公開しない must never hide a conflicting authored item.
enum SummaryContentProjection {
  static func supplements(_ items: [String], markdown: String) -> [String] {
    let statements = Set(MarkdownBlockParser.blocks(for: markdown).compactMap { block -> String? in
      switch block {
      case .paragraph(let text), .bullet(_, _, let text): normalized(text)
      default: nil
      }
    })
    var seen = Set<String>()
    return items.filter { item in
      let key = normalized(item)
      return !key.isEmpty && !statements.contains(key) && seen.insert(key).inserted
    }
  }

  private static func normalized(_ value: String) -> String {
    // A link's visible label cannot establish equality of its destination.
    let text = value.contains("](") || value.contains("<") ? value : MarkdownBlockParser.plainText(value)
    return text
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
