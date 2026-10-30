import Foundation
import CoreGraphics
import CoreText

// Print uses fixed point sizes; device text size and appearance never change a shared file.
enum DocumentPDFLayout {
  static let pageSize = CGSize(width: 595, height: 842)
  static let margin: CGFloat = 48
  static let bodyBottom = pageSize.height - margin
  static let bodyHeight = bodyBottom - margin
  static let bodyWidth = pageSize.width - margin * 2

  struct Line {
    var text: String
    var glyphs: CTLine
    var ascent: CGFloat
    var height: CGFloat
  }

  struct Text {
    var line: Line
    var x: CGFloat
    var top: CGFloat
    var width: CGFloat
  }

  struct Page {
    var text: [Text] = []
    var borders: [CGRect] = []
    var fills: [CGRect] = []
  }

  struct Builder {
    private(set) var pages: [Page] = [Page()]
    private var y = margin
    private var followsHeading = false

    mutating func append(_ blocks: [MarkdownBlock]) throws {
      for (index, block) in blocks.enumerated() {
        if case .heading = block {
          var probe = Builder()
          try probe.append(block)
          var minimum = probe.y - margin
          for following in blocks.dropFirst(index + 1).prefix(8) {
            switch following {
            case .heading, .rule: break
            default: minimum = probe.y - margin + DocumentPDFLayout.minimumStartHeight(of: following)
            }
            try probe.append(DocumentPDFLayout.firstPart(of: following))
            switch following {
            case .heading, .rule: continue
            default: break
            }
            break
          }
          let headingGap: CGFloat = y == margin ? 0 : 10
          let needed = probe.pages.count == 1 ? probe.y - margin : minimum
          ensureSpace(min(bodyHeight, needed + headingGap))
        }
        try append(block)
      }
    }

    mutating func appendTitle(_ title: String, date: String) throws {
      try appendText(title, size: 23, bold: true, gap: 6, keepNext: 36)
      try appendText(date, size: 10, gap: 22)
    }

    mutating func append(_ block: MarkdownBlock) throws {
      try Task.checkCancellation()
      let afterHeading = followsHeading
      followsHeading = false
      switch block {
      case .heading(let level, let text):
        y += y == margin ? 0 : 10
        try appendText(text, size: level == 1 ? 21 : (level == 2 ? 17 : 14), bold: true, gap: 7, keepNext: 42)
        followsHeading = true
      case .paragraph(let text):
        try appendText(text, keepsWhole: !afterHeading)
      case .bullet(let level, let marker, let text):
        let prefix: String
        switch marker {
        case .dot: prefix = "• "
        case .number(let value): prefix = "\(value). "
        case .checkbox(let checked): prefix = checked ? "☑ " : "☐ "
        }
        try appendText(prefix + text, inset: CGFloat(min(level, 4)) * 14, gap: 6, keepsWhole: !afterHeading)
      case .quote(let text):
        try appendText(text, inset: 16, quoteBar: true, keepsWhole: !afterHeading)
      case .code(_, let text):
        try appendText(text, size: 11, literal: true, keepsWhole: !afterHeading)
      case .rule:
        ensureSpace(16)
        pages[pages.count - 1].borders.append(CGRect(x: margin, y: y + 4, width: bodyWidth, height: 0))
        y += 16
        followsHeading = afterHeading
      case .table(let header, let rows):
        try appendTable(header: header, rows: rows, afterHeading: afterHeading)
      }
    }

    private mutating func newPage() {
      guard !pages[pages.count - 1].text.isEmpty || !pages[pages.count - 1].borders.isEmpty else { y = margin; return }
      pages.append(Page())
      y = margin
    }

    private mutating func ensureSpace(_ height: CGFloat) {
      if y > margin && height > bodyBottom - y { newPage() }
    }

    private mutating func appendText(_ text: String, size: CGFloat = 13, bold: Bool = false,
                                     literal: Bool = false, inset: CGFloat = 0, gap: CGFloat = 11,
                                     keepNext: CGFloat = 0, quoteBar: Bool = false, keepsWhole: Bool = true) throws {
      let lines = try DocumentPDFLayout.lines(text, width: bodyWidth - inset, size: size, bold: bold, literal: literal)
      let height = lines.reduce(0) { $0 + $1.height }
      // Keep a paragraph together when it fits a page. An oversized paragraph flows by complete lines.
      if keepsWhole && height + keepNext <= bodyHeight { ensureSpace(height + keepNext) }
      for (index, line) in lines.enumerated() {
        try Task.checkCancellation()
        let remaining = lines.count - index
        if index == 0 && remaining > 1 { ensureSpace(line.height + lines[index + 1].height) }
        ensureSpace(line.height)
        if quoteBar { pages[pages.count - 1].borders.append(CGRect(x: margin + 4, y: y, width: 0, height: line.height)) }
        place(line, x: margin + inset, width: bodyWidth - inset)
      }
      y += gap
    }

    private mutating func place(_ line: Line, x: CGFloat, width: CGFloat) {
      pages[pages.count - 1].text.append(Text(line: line, x: x, top: y, width: width))
      y += line.height
    }

    private mutating func appendTable(header: [String], rows: [[String]], afterHeading: Bool) throws {
      let columns = max(header.count, rows.map(\.count).max() ?? 0)
      guard columns > 0 else { return }
      // A wide table becomes labeled records on A4, rather than unreadably narrow Japanese columns.
      if columns > 4 {
        for (index, row) in rows.enumerated() {
          try Task.checkCancellation()
          let entries = row.enumerated().map { index, value in
            let label = header.indices.contains(index) ? header[index] : "項目\(index + 1)"
            return (label.isEmpty ? "" : label + ": ") + value
          }
          let combined = entries.joined(separator: "\n")
          try appendText(combined, keepsWhole: !(index == 0 && afterHeading))
        }
        if rows.isEmpty { try appendText(header.joined(separator: " / "), bold: true) }
        return
      }
      let width = bodyWidth / CGFloat(columns)
      let padding: CGFloat = 7
      let headers = try (0..<columns).map { column in
        try DocumentPDFLayout.lines(header.indices.contains(column) ? header[column] : "", width: width - padding * 2, size: 11, bold: true)
      }
      let headerHeight = (headers.map { $0.reduce(0) { $0 + $1.height } }.max() ?? 0) + padding * 2
      // Unusually long headings must still be printed in full, without trapping pagination.
      if headerHeight > bodyHeight / 3 {
        try appendText(header.joined(separator: " / "), bold: true, keepsWhole: !afterHeading)
        for row in rows { try appendText(row.joined(separator: " / ")) }
        return
      }
      ensureSpace(headerHeight + 40)
      drawTableBand(headers, offsets: Array(repeating: 0, count: columns), counts: headers.map(\.count),
                    width: width, height: headerHeight, shaded: true)
      for (index, row) in rows.enumerated() {
        try Task.checkCancellation()
        let cells = try (0..<columns).map { column in
          try DocumentPDFLayout.lines(row.indices.contains(column) ? row[column] : "", width: width - padding * 2, size: 11)
        }
        let fullHeight = (cells.map { $0.reduce(0) { $0 + $1.height } }.max() ?? 0) + padding * 2
        if !(index == 0 && afterHeading) && fullHeight <= bodyHeight - headerHeight && fullHeight > bodyBottom - y {
          newPage()
          drawTableBand(headers, offsets: Array(repeating: 0, count: columns), counts: headers.map(\.count),
                        width: width, height: headerHeight, shaded: true)
        }
        var offsets = Array(repeating: 0, count: columns)
        while offsets.enumerated().contains(where: { $0.element < cells[$0.offset].count }) {
          try Task.checkCancellation()
          let minimumLine = cells.enumerated().compactMap { index, lines in offsets[index] < lines.count ? lines[offsets[index]].height : nil }.max() ?? 0
          if minimumLine + padding * 2 > bodyBottom - y {
            newPage()
            drawTableBand(headers, offsets: Array(repeating: 0, count: columns), counts: headers.map(\.count),
                          width: width, height: headerHeight, shaded: true)
          }
          let available = bodyBottom - y - padding * 2
          var counts = Array(repeating: 0, count: columns)
          var height: CGFloat = 0
          for column in 0..<columns {
            var used: CGFloat = 0
            for line in cells[column].dropFirst(offsets[column]) {
              if used + line.height > available { break }
              used += line.height
              counts[column] += 1
            }
            height = max(height, used)
          }
          guard counts.contains(where: { $0 > 0 }) else { throw DocumentPDFError.layoutFailed }
          var drawnOffsets = offsets, drawnCounts = counts
          for column in 0..<columns where offsets[column] == cells[column].count && cells[column].count <= 3 {
            // Repeat the row's short identifiers when another cell continues onto a new page.
            drawnOffsets[column] = 0
            drawnCounts[column] = cells[column].count
            height = max(height, cells[column].reduce(0) { $0 + $1.height })
          }
          drawTableBand(cells, offsets: drawnOffsets, counts: drawnCounts, width: width, height: height + padding * 2, shaded: false)
          for column in 0..<columns { offsets[column] += counts[column] }
        }
      }
      y += 12
    }

    private mutating func drawTableBand(_ cells: [[Line]], offsets: [Int], counts: [Int], width: CGFloat,
                                       height: CGFloat, shaded: Bool) {
      let top = y
      if shaded { pages[pages.count - 1].fills.append(CGRect(x: margin, y: top, width: bodyWidth, height: height)) }
      for column in cells.indices {
        let x = margin + CGFloat(column) * width
        pages[pages.count - 1].borders.append(CGRect(x: x, y: top, width: width, height: height))
        y = top + 7
        for line in cells[column].dropFirst(offsets[column]).prefix(counts[column]) {
          place(line, x: x + 7, width: width - 14)
        }
      }
      y = top + height
    }
  }

  private static func firstPart(of block: MarkdownBlock) -> MarkdownBlock {
    switch block {
    case .paragraph(let text): return .paragraph(String(text.prefix(4_000)))
    case .quote(let text): return .quote(String(text.prefix(4_000)))
    case .code(let language, let text): return .code(language: language, text: String(text.prefix(4_000)))
    case .bullet(let level, let marker, let text): return .bullet(level: level, marker: marker, text: String(text.prefix(4_000)))
    case .table(let header, let rows):
      let columns = max(header.count, rows.map(\.count).max() ?? 0)
      let first = rows.first.map { $0.map { String($0.prefix(4_000)) } + Array(repeating: "", count: max(0, columns - $0.count)) }
      return .table(header: header, rows: first.map { [$0] } ?? [])
    default: return block
    }
  }

  private static func minimumStartHeight(of block: MarkdownBlock) -> CGFloat {
    guard case .table(let header, let rows) = block else { return 44 }
    let columns = max(header.count, rows.map(\.count).max() ?? 0)
    guard (1...4).contains(columns) else { return 44 }
    let width = bodyWidth / CGFloat(columns) - 14
    let height = header.map { text in
      (try? lines(text, width: width, size: 11, bold: true).reduce(0) { $0 + $1.height }) ?? 0
    }.max() ?? 0
    return height + 14 <= bodyHeight / 3 ? height + 14 + 40 : 44
  }

  static func lines(_ text: String, width: CGFloat, size: CGFloat, bold: Bool = false, literal: Bool = false) throws -> [Line] {
    let attributed = styled(text, size: size, bold: bold, literal: literal)
    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    var result: [Line] = []
    var offset = 0
    let string = attributed.string as NSString
    while offset < attributed.length {
      try Task.checkCancellation()
      let count = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
      let clusterCount = count > 0 ? count : CTTypesetterSuggestClusterBreak(typesetter, offset, Double(width))
      let length = clusterCount > 0 ? clusterCount : string.rangeOfComposedCharacterSequence(at: offset).length
      let range = CFRange(location: offset, length: length)
      let line = CTTypesetterCreateLine(typesetter, range)
      var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      result.append(Line(text: string.substring(with: NSRange(location: offset, length: length)), glyphs: line,
                         ascent: max(ascent, size), height: ceil(max(size * 1.5, ascent + descent + leading + 3))))
      offset += length
    }
    if result.isEmpty {
      let empty = CTLineCreateWithAttributedString(styled(" ", size: size, bold: bold))
      result = [Line(text: "", glyphs: empty, ascent: size, height: ceil(size * 1.5))]
    }
    return result
  }

  static func styled(_ text: String, size: CGFloat, bold: Bool, literal: Bool = false) -> NSAttributedString {
    let base = CTFontCreateUIFontForLanguage(literal ? .userFixedPitch : .system, size, nil)!
    func font(_ strong: Bool, _ italic: Bool) -> CTFont {
      var traits: CTFontSymbolicTraits = []
      if strong { traits.insert(.boldTrait) }
      if italic { traits.insert(.italicTrait) }
      return traits.isEmpty ? base : CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
    }
    let parsed = literal ? AttributedString(text) :
      ((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    let result = NSMutableAttributedString(string: "")
    for run in parsed.runs {
      let intent = run.inlinePresentationIntent ?? []
      let piece = String(parsed[run.range].characters)
      var attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font(bold || intent.contains(.stronglyEmphasized), intent.contains(.emphasized)),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)
      ]
      if intent.contains(.code) {
        attributes[NSAttributedString.Key(kCTFontAttributeName as String)] = CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
      }
      if let url = run.link {
        attributes[NSAttributedString.Key("MemoraPDFURL")] = url
        attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = CTUnderlineStyle.single.rawValue
      }
      if intent.contains(.strikethrough) { attributes[NSAttributedString.Key("MemoraPDFStrike")] = true }
      result.append(NSAttributedString(string: piece, attributes: attributes))
    }
    return result
  }
}
