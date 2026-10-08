import Foundation

/// Writes an edited block back into its document, touching only the lines the
/// block came from, so the rest of the document stays exactly as it was.
enum MarkdownBlockWriter {
  /// The document with one block replaced, or removed when `block` is nil.
  static func replacing(_ sourced: SourcedMarkdownBlock, with block: MarkdownBlock?, in markdown: String) -> String {
    var lines = markdown.components(separatedBy: "\n")
    let range = clamped(sourced.lines, count: lines.count)
    let original = Array(lines[range])
    lines.replaceSubrange(range, with: block.map { source(of: $0, original: original) } ?? [])
    return lines.joined(separator: "\n")
  }

  /// The document with a block added right after another.
  static func inserting(_ block: MarkdownBlock, after sourced: SourcedMarkdownBlock, in markdown: String) -> String {
    var lines = markdown.components(separatedBy: "\n")
    let index = min(sourced.lines.upperBound, lines.count)
    var inserted = source(of: block, original: [])
    if case .table = block { inserted = [""] + inserted + [""] }
    lines.insert(contentsOf: inserted, at: index)
    return lines.joined(separator: "\n")
  }

  /// The next list item after this one: the same kind, at the same depth.
  static func nextItem(after block: MarkdownBlock) -> MarkdownBlock? {
    guard case .bullet(let level, let marker, _) = block else { return nil }
    switch marker {
    case .dot:
      return .bullet(level: level, marker: .dot, text: "")
    case .number(let number):
      return .bullet(level: level, marker: .number(String((Int(number) ?? 0) + 1)), text: "")
    case .checkbox:
      return .bullet(level: level, marker: .checkbox(isChecked: false), text: "")
    }
  }

  static func source(of block: MarkdownBlock, original: [String]) -> [String] {
    switch block {
    case .heading(let level, let text):
      return [String(repeating: "#", count: max(1, level)) + " " + oneLine(text)]
    case .paragraph(let text):
      return text.components(separatedBy: "\n")
    case .bullet(let level, let marker, let text):
      let indent = String(repeating: " ", count: level * 2)
      let prefix = switch marker {
      case .dot: "- "
      case .number(let number): "\(number). "
      case .checkbox(let isChecked): isChecked ? "- [x] " : "- [ ] "
      }
      return [indent + prefix + oneLine(text)]
    case .quote(let text):
      return ["> " + oneLine(text)]
    case .table(let header, let rows):
      // The alignment row is kept as it was written.
      let separator = original.first { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.allSatisfy { "|-: ".contains($0) }
          && trimmed.split(separator: "|").count == header.count
      } ?? "|" + String(repeating: ":---|", count: header.count)
      return [row(header), separator] + rows.map(row)
    case .rule:
      return ["---"]
    }
  }

  private static func row(_ cells: [String]) -> String {
    "| " + cells.map { oneLine($0).replacingOccurrences(of: "|", with: "／") }.joined(separator: " | ") + " |"
  }

  private static func oneLine(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: " ")
  }

  private static func clamped(_ range: Range<Int>, count: Int) -> Range<Int> {
    let lower = min(max(0, range.lowerBound), count)
    let upper = min(max(lower, range.upperBound), count)
    return lower..<upper
  }
}
