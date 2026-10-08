import Foundation

enum MarkdownEditingAction {
  case paragraph, heading, bullet, numbered, checklist, toggleCheck
  case table, addRow, addColumn, deleteRow, deleteColumn

  static func applying(_ action: Self, to markdown: String, selection: NSRange) -> String {
    let source = markdown as NSString
    let location = min(selection.location, source.length)
    let lineIndex = source.substring(to: location).components(separatedBy: "\n").count - 1
    if let sourced = MarkdownBlockParser.sourcedBlocks(for: markdown).first(where: { $0.lines.contains(lineIndex) }),
       case .table(var header, var rows) = sourced.block {
      switch action {
      case .addRow: rows.append(Array(repeating: "", count: header.count))
      case .addColumn:
        header.append("見出し")
        rows = rows.map { $0 + [""] }
      case .deleteRow:
        let row = lineIndex - sourced.lines.lowerBound - 2
        guard rows.count > 1, rows.indices.contains(row) else { return markdown }
        rows.remove(at: row)
      case .deleteColumn:
        guard header.count > 1 else { return markdown }
        header.removeLast()
        rows = rows.map { Array($0.prefix(header.count)) }
      default: return markdown
      }
      return MarkdownBlockWriter.replacing(sourced, with: .table(header: header, rows: rows), in: markdown)
    }
    let range = source.paragraphRange(for: NSRange(location: location, length: 0))
    let original = source.substring(with: range).trimmingCharacters(in: .newlines)
    let parsed = MarkdownBlockParser.sourcedBlocks(for: original).first?.block
    let text: String
    switch parsed {
    case .heading(_, let value), .paragraph(let value), .bullet(_, _, let value), .quote(let value): text = value
    default: text = original
    }
    let block: MarkdownBlock
    switch action {
    case .paragraph: block = .paragraph(text)
    case .heading: block = .heading(level: 2, text: text)
    case .bullet: block = .bullet(level: 0, marker: .dot, text: text)
    case .numbered: block = .bullet(level: 0, marker: .number("1"), text: text)
    case .checklist: block = .bullet(level: 0, marker: .checkbox(isChecked: false), text: text)
    case .toggleCheck:
      guard case .bullet(let level, .checkbox(let checked), let value) = parsed else { return markdown }
      block = .bullet(level: level, marker: .checkbox(isChecked: !checked), text: value)
    case .table:
      let table = "\n\n| 項目 | 内容 |\n| --- | --- |\n| 項目1 | 内容1 |\n"
      return source.replacingCharacters(in: NSRange(location: NSMaxRange(range), length: 0), with: table)
    default: return markdown
    }
    let replacement = MarkdownBlockWriter.source(of: block, original: []).joined(separator: "\n")
    return source.replacingCharacters(in: range, with: replacement + (source.substring(with: range).hasSuffix("\n") ? "\n" : ""))
  }
}
