import Foundation

/// Reads the block structure of a markdown document: headings, lists, quotes,
/// tables and rules. Inline styling inside each block is left to
/// `AttributedString`, which only understands inline markdown.
enum MarkdownBlockParser {
  /// True for a document with headings or tables, which is what a generated
  /// summary looks like. Plain notes keep their single-text look.
  static func hasBlockStructure(_ markdown: String) -> Bool {
    markdown.split(separator: "\n", omittingEmptySubsequences: true).contains { line in
      let trimmed = line.drop { $0 == " " }
      return trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ")
        || trimmed.hasPrefix("|")
    }
  }

  static func blocks(for markdown: String) -> [MarkdownBlock] {
    if let cached = cache.object(forKey: markdown as NSString) {
      return cached.blocks
    }
    let blocks = parse(markdown)
    cache.setObject(Box(blocks), forKey: markdown as NSString)
    return blocks
  }

  /// The passage a document offers as its gist, as plain text: the text after
  /// a 概要 label, else the paragraph under a 概要／要旨 heading, else its
  /// first paragraph that is more than 日時／参加者 labels.
  static func overview(of markdown: String) -> String {
    if let cached = overviewCache.object(forKey: markdown as NSString) {
      return cached as String
    }
    var labelled: String?
    var underHeading: String?
    var firstParagraph: String?
    var inOverviewSection = false

    for block in blocks(for: markdown) {
      switch block {
      case .heading(_, let text):
        inOverviewSection = text.contains("概要") || text.contains("要旨")
      case .paragraph(let text):
        labelled = labelled ?? passageAfterOverviewLabel(in: text)
        if inOverviewSection { underHeading = underHeading ?? text }
        if !isLabelsOnly(text) { firstParagraph = firstParagraph ?? text }
      default:
        break
      }
      if labelled != nil { break }
    }

    let plain = plainText(labelled ?? underHeading ?? firstParagraph ?? "")
    overviewCache.setObject(plain as NSString, forKey: markdown as NSString)
    return plain
  }

  /// "**会議の概要**: text" or the label on its own line with the text below.
  private static func passageAfterOverviewLabel(in paragraph: String) -> String? {
    let lines = paragraph.components(separatedBy: "\n")
    guard let index = lines.firstIndex(where: { $0.contains("概要**") }) else { return nil }
    let label = lines[index]
    let sameLine = label.range(of: "**:").map { String(label[$0.upperBound...]) }
      ?? label.range(of: "**：").map { String(label[$0.upperBound...]) }
      ?? ""
    let passage = ([sameLine] + lines[(index + 1)...])
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return passage.isEmpty ? nil : passage
  }

  private static func isLabelsOnly(_ paragraph: String) -> Bool {
    paragraph.components(separatedBy: "\n").allSatisfy { $0.hasPrefix("**") }
  }

  /// Inline markdown read as the words it shows.
  static func plainText(_ markdown: String) -> String {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let attributed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    return String(attributed.characters)
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func parse(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var tableLines: [String] = []

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      blocks.append(.paragraph(paragraph.joined(separator: "\n")))
      paragraph = []
    }
    func flushTable() {
      guard !tableLines.isEmpty else { return }
      let rows = tableLines
        .map(cells)
        .filter { row in !row.allSatisfy { $0.allSatisfy { "-: ".contains($0) } } }
      if let header = rows.first {
        blocks.append(.table(header: header, rows: Array(rows.dropFirst())))
      }
      tableLines = []
    }

    for rawLine in markdown.components(separatedBy: "\n") {
      let indent = rawLine.prefix { $0 == " " || $0 == "\t" }
        .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
      let line = rawLine.trimmingCharacters(in: .whitespaces)

      if line.hasPrefix("|") {
        flushParagraph()
        tableLines.append(line)
        continue
      }
      flushTable()

      if line.isEmpty {
        flushParagraph()
        continue
      }
      if line == "---" || line == "***" || line == "___" {
        flushParagraph()
        blocks.append(.rule)
        continue
      }
      if let heading = heading(line) {
        flushParagraph()
        blocks.append(heading)
        continue
      }
      if line.hasPrefix(">") {
        flushParagraph()
        blocks.append(.quote(line.drop { $0 == ">" || $0 == " " }.description))
        continue
      }
      if let (marker, text) = listItem(line) {
        flushParagraph()
        blocks.append(.bullet(level: indent / 2, marker: marker, text: text))
        continue
      }
      paragraph.append(line)
    }
    flushParagraph()
    flushTable()
    return blocks
  }

  private static func heading(_ line: String) -> MarkdownBlock? {
    let hashes = line.prefix { $0 == "#" }.count
    guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return .heading(level: hashes, text: line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
  }

  private static func listItem(_ line: String) -> (MarkdownBlock.Marker, String)? {
    for (prefix, checked) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] where line.hasPrefix(prefix) {
      return (.checkbox(isChecked: checked), String(line.dropFirst(prefix.count)))
    }
    if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
      return (.dot, String(line.dropFirst(2)))
    }
    let digits = line.prefix { $0.isASCII && $0.isNumber }
    if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
      return (.number(String(digits)), String(line.dropFirst(digits.count + 2)))
    }
    return nil
  }

  private static func cells(_ line: String) -> [String] {
    var cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    if cells.first?.isEmpty == true { cells.removeFirst() }
    if cells.last?.isEmpty == true { cells.removeLast() }
    return cells
  }

  private static let overviewCache: NSCache<NSString, NSString> = {
    let cache = NSCache<NSString, NSString>()
    cache.countLimit = 500
    return cache
  }()

  /// Parsing is reused across redraws of the same summary.
  private static let cache: NSCache<NSString, Box> = {
    let cache = NSCache<NSString, Box>()
    cache.countLimit = 50
    return cache
  }()

  private final class Box {
    let blocks: [MarkdownBlock]
    init(_ blocks: [MarkdownBlock]) { self.blocks = blocks }
  }
}
