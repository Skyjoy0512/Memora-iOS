import Foundation

/// Reads the block structure of a markdown document: headings, lists, quotes,
/// tables and rules. Inline styling inside each block is left to
/// `AttributedString`, which only understands inline markdown.
enum MarkdownBlockParser {
  /// True for a document with headings or tables, which is what a generated
  /// summary looks like. Plain notes keep their single-text look.
  /// True when text uses any markdown worth drawing: list markers, headings,
  /// quotes, tables, or bold. Used for chat answers, which are often lists.
  static func hasInlineOrBlockMarkdown(_ text: String) -> Bool {
    if text.contains("**") || text.contains("```") || text.contains("~~~") || hasBlockStructure(text) { return true }
    return text.split(separator: "\n").contains { line in
      let trimmed = line.drop { $0 == " " }
      if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("> ") { return true }
      // A numbered item: digits, then ". ".
      let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
      return !digits.isEmpty && trimmed.dropFirst(digits.count).hasPrefix(". ")
    }
  }

  /// Remembered per text, since screens and list rows ask on every redraw and
  /// a long summary would otherwise be split into lines each time.
  static func hasBlockStructure(_ markdown: String) -> Bool {
    let key = markdown as NSString
    if let cached = structureCache.object(forKey: key) {
      return cached.boolValue
    }
    let result = markdown.split(separator: "\n", omittingEmptySubsequences: true).contains { line in
      let trimmed = line.drop { $0 == " " }
      return trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ")
        || trimmed.hasPrefix("|")
    }
    structureCache.setObject(NSNumber(value: result), forKey: key)
    return result
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
    sourcedBlocks(for: markdown).map(\.block)
  }

  /// Each block with the source lines it was read from, so an edit to one
  /// block can be written back over exactly those lines.
  static func sourcedBlocks(for markdown: String) -> [SourcedMarkdownBlock] {
    var blocks: [SourcedMarkdownBlock] = []
    var paragraph: [String] = []
    var paragraphStart = 0
    var tableLines: [String] = []
    var tableStart = 0
    var lineIndex = 0
    var lineCount = 0
    var fence: MarkdownFence?
    var codeLines: [String] = []
    var codeStart = 0

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      blocks.append(SourcedMarkdownBlock(
        block: .paragraph(paragraph.joined(separator: "\n")),
        lines: paragraphStart..<lineIndex
      ))
      paragraph = []
    }
    func flushTable() {
      guard !tableLines.isEmpty else { return }
      let rows = tableLines
        .map(cells)
        .filter { row in !row.allSatisfy { $0.allSatisfy { "-: ".contains($0) } } }
      if let header = rows.first {
        blocks.append(SourcedMarkdownBlock(
          block: .table(header: header, rows: Array(rows.dropFirst())),
          lines: tableStart..<lineIndex
        ))
      }
      tableLines = []
    }
    func append(_ block: MarkdownBlock) {
      blocks.append(SourcedMarkdownBlock(block: block, lines: lineIndex..<(lineIndex + 1)))
    }

    for (index, sourceLine) in markdown.components(separatedBy: "\n").enumerated() {
      let rawLine = sourceLine.hasSuffix("\r") ? String(sourceLine.dropLast()) : sourceLine
      lineIndex = index
      lineCount = index + 1
      if let open = fence {
        if open.closes(rawLine) {
          blocks.append(SourcedMarkdownBlock(block: .code(language: open.language, text: codeLines.joined(separator: "\n")), lines: codeStart..<(index + 1)))
          fence = nil
          codeLines = []
        } else { codeLines.append(rawLine) }
        continue
      }
      if let open = MarkdownFence(rawLine) {
        flushParagraph()
        flushTable()
        fence = open
        codeStart = index
        continue
      }
      let indent = rawLine.prefix { $0 == " " || $0 == "\t" }
        .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
      let line = rawLine.trimmingCharacters(in: .whitespaces)

      if line.hasPrefix("|") {
        flushParagraph()
        if tableLines.isEmpty { tableStart = index }
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
        append(.rule)
        continue
      }
      if let heading = heading(line) {
        flushParagraph()
        append(heading)
        continue
      }
      if line.hasPrefix(">") {
        flushParagraph()
        append(.quote(line.drop { $0 == ">" || $0 == " " }.description))
        continue
      }
      if let (marker, text) = listItem(line) {
        flushParagraph()
        append(.bullet(level: indent / 2, marker: marker, text: text))
        continue
      }
      if paragraph.isEmpty { paragraphStart = index }
      paragraph.append(line)
    }
    lineIndex = lineCount
    if let open = fence {
      blocks.append(SourcedMarkdownBlock(block: .code(language: open.language, text: codeLines.joined(separator: "\n")), lines: codeStart..<lineIndex))
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
    // An item still being written has no text yet, and its trailing space
    // is trimmed away with the line's.
    switch line {
    case "-", "*", "+": return (.dot, "")
    case "- [ ]": return (.checkbox(isChecked: false), "")
    case "- [x]", "- [X]": return (.checkbox(isChecked: true), "")
    default: break
    }
    if line.hasSuffix("."), !line.dropLast().isEmpty, line.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }) {
      return (.number(String(line.dropLast())), "")
    }
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

  private static let structureCache: NSCache<NSString, NSNumber> = {
    let cache = NSCache<NSString, NSNumber>()
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
