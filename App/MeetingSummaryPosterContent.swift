import Foundation

/// A source-ordered visual excerpt, never a second interpretation of the meeting.
struct MeetingSummaryPosterContent: Equatable {
  var title: String
  var date: String
  var sections: [MeetingSummaryPosterSection] = []
  var hasOmissions = false
  var fullSummary: String

  init(title: String, date: String, summary: String) {
    self.title = Self.excerpt(title, limit: 64)
    self.date = date
    fullSummary = summary
    var headings: [(level: Int, text: String)] = []
    var current = MeetingSummaryPosterSection(id: 0, headings: [])
    var listLevel: Int?

    func flush() {
      if !current.groups.isEmpty { sections.append(current) }
    }

    for source in MarkdownBlockParser.sourcedBlocks(for: summary) {
      let id = source.lines.lowerBound
      switch source.block {
      case .heading(let level, let text):
        flush()
        headings.removeAll { $0.level >= level }
        headings.append((level, MarkdownBlockParser.plainText(text)))
        current = MeetingSummaryPosterSection(id: id + 1, headings: headings.map(\.text))
        listLevel = nil
      case .bullet(let level, let marker, let text):
        let prefix: String
        switch marker {
        case .dot: prefix = "•"
        case .number(let number): prefix = number
        case .checkbox(let checked): prefix = checked ? "☑" : "☐"
        }
        if let base = listLevel, level > base, !current.groups.isEmpty {
          current.groups[current.groups.count - 1].lines.append(
            .init(id: id, depth: level - base, prefix: "", text: MarkdownBlockParser.plainText(text)))
        } else {
          listLevel = level
          current.groups.append(.init(id: id, lines: [
            .init(id: id, depth: 0, prefix: prefix, text: MarkdownBlockParser.plainText(text))
          ]))
        }
      case .table(let header, let rows):
        listLevel = nil
        for (rowIndex, row) in rows.enumerated() {
          // IDs are source locations within this immutable render snapshot, not live list positions.
          let lines = row.enumerated().compactMap { column, value -> MeetingSummaryPosterSection.Line? in
            let plain = MarkdownBlockParser.plainText(value)
            guard !plain.isEmpty else { return nil }
            let label = column < header.count ? MarkdownBlockParser.plainText(header[column]) : ""
            return .init(id: column, depth: column == 0 ? 0 : 1, prefix: "",
                         text: label.isEmpty ? plain : label + "：" + plain)
          }
          if !lines.isEmpty { current.groups.append(.init(id: id + rowIndex, lines: lines)) }
        }
      case .paragraph(let text), .quote(let text), .code(_, let text):
        listLevel = nil
        let plain = MarkdownBlockParser.plainText(text)
        if !plain.isEmpty {
          current.groups.append(.init(id: id, lines: [.init(id: id, depth: 0, prefix: "", text: plain)]))
        }
      case .rule:
        listLevel = nil
      }
    }
    flush()
    // Bound work before rendering; the original document remains available below.
    if sections.count > 8 { sections = Array(sections.prefix(8)); hasOmissions = true }
    for index in sections.indices {
      sections[index].headings = sections[index].headings.map { heading in
        if heading.count > 80 { hasOmissions = true }
        return Self.excerpt(heading, limit: 80)
      }
      if sections[index].groups.count > 3 {
        sections[index].groups = Array(sections[index].groups.prefix(3))
        hasOmissions = true
      }
      for groupIndex in sections[index].groups.indices {
        let group = sections[index].groups[groupIndex]
        let lineLimit = group.lines.count > 1 ? 90 : 320
        if group.lines.count > 6 || group.lines.contains(where: { $0.text.count > lineLimit }) {
          sections[index].groups[groupIndex].lines = Array(group.lines.prefix(6)).map { line in
            var line = line
            line.text = Self.excerpt(line.text, limit: lineLimit)
            return line
          }
          hasOmissions = true
        }
      }
    }
  }

  /// Reduce a whole group, never discard just its qualifiers to make it fit.
  mutating func reduceToFit() -> Bool {
    if let index = sections.lastIndex(where: { $0.groups.count > 1 }) {
      sections[index].groups.removeLast()
    } else if sections.count > 1 {
      sections.removeLast()
    } else {
      return false
    }
    hasOmissions = true
    return true
  }

  static func excerpt(_ text: String, limit: Int) -> String {
    let plain = MarkdownBlockParser.plainText(text)
    return plain.count > limit ? String(plain.prefix(limit - 1)) + "…" : plain
  }
}
