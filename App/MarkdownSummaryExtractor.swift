import Foundation

/// Reads decisions, open questions and actions back out of a summary document,
/// for replies that came without their data block.
enum MarkdownSummaryExtractor {
  struct Extracted {
    var decisions: [String] = []
    var openQuestions: [String] = []
    var actions: [SummaryActionItem] = []
  }

  static func extract(from markdown: String) -> Extracted {
    var result = Extracted()
    var section = Section.other
    var tableHeader: [String]?
    var bulletActions: [SummaryActionItem] = []

    for rawLine in markdown.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespaces)

      if line.hasPrefix("#") {
        section = Section(heading: line)
        tableHeader = nil
        continue
      }
      // A bold label inside a bullet ("- **決定事項**:") opens a sub-section.
      if let label = boldLabel(in: line) {
        section = Section(heading: label)
        continue
      }

      if line.hasPrefix("|") {
        let cells = tableCells(line)
        if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue }
        guard let header = tableHeader else {
          tableHeader = cells
          continue
        }
        if let action = action(from: cells, header: header) {
          result.actions.append(action)
        }
        continue
      }
      tableHeader = nil

      guard let item = bulletText(line), SummaryActionItem.normalized(item) != nil else { continue }
      switch section {
      case .decisions:
        result.decisions.append(item)
      case .questions:
        result.openQuestions.append(item)
      case .actions:
        bulletActions.append(action(fromBullet: item))
      case .other:
        break
      }
    }
    // A table is the authoritative list; bullets such as 予定アクション only
    // stand in when a document has no table, so nothing is filed twice.
    if result.actions.isEmpty {
      result.actions = bulletActions
    }
    result.actions = SummaryResponseParser.deduplicated(result.actions)
    return result
  }

  private enum Section {
    case decisions, questions, actions, other

    init(heading: String) {
      if heading.contains("決定") {
        self = .decisions
      } else if heading.contains("未決") || heading.contains("オープンクエスチョン") || heading.contains("未解決") {
        self = .questions
      } else if heading.contains("アクション") || heading.contains("今後の予定") {
        self = .actions
      } else {
        self = .other
      }
    }
  }

  private static func boldLabel(in line: String) -> String? {
    guard line.hasPrefix("- **") || line.hasPrefix("* **") else { return nil }
    let body = line.dropFirst(4)
    guard let end = body.range(of: "**") else { return nil }
    let rest = body[end.upperBound...].trimmingCharacters(in: .whitespaces)
    // Only a label that introduces nested items, not "**x**: value" on one line.
    guard rest == ":" || rest == "：" || rest.isEmpty else { return nil }
    return String(body[..<end.lowerBound])
  }

  private static func bulletText(_ line: String) -> String? {
    var text = line
    if text.hasPrefix("- [ ] ") || text.hasPrefix("- [x] ") {
      text.removeFirst(6)
    } else if text.hasPrefix("- ") || text.hasPrefix("* ") || text.hasPrefix("・") {
      text.removeFirst(text.hasPrefix("・") ? 1 : 2)
    } else {
      return nil
    }
    text = text.replacingOccurrences(of: "[???]", with: "").trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : text
  }

  private static func tableCells(_ line: String) -> [String] {
    var cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    if cells.first?.isEmpty == true { cells.removeFirst() }
    if cells.last?.isEmpty == true { cells.removeLast() }
    return cells
  }

  private static func action(from cells: [String], header: [String]) -> SummaryActionItem? {
    func value(_ names: [String]) -> String? {
      guard let index = header.firstIndex(where: { column in names.contains { column.contains($0) } }),
            cells.indices.contains(index) else { return nil }
      return cells[index]
    }
    guard let title = value(["タイトル", "件名", "アクション", "内容"]), !title.isEmpty else { return nil }
    return SummaryActionItem(
      title: title,
      detail: value(["説明", "詳細"]) ?? "",
      owner: SummaryActionItem.normalized(value(["責任者", "担当"])),
      due: SummaryActionItem.normalized(value(["期限", "期日"]))
    )
  }

  /// Reads "内容（担当: X / 期限: Y）" and "@X - 内容 - 期限: Y" bullets.
  private static func action(fromBullet text: String) -> SummaryActionItem {
    var title = text
    var owner: String?
    var due: String?

    if text.hasPrefix("@") || text.hasPrefix("＠") {
      let parts = text.components(separatedBy: " - ")
      owner = SummaryActionItem.normalized(parts.first)
      title = parts.count > 1 ? parts[1] : text
      if let last = parts.last, parts.count > 2 {
        due = SummaryActionItem.normalized(last.replacingOccurrences(of: "期限:", with: ""))
      }
    } else if let open = text.firstIndex(where: { $0 == "（" || $0 == "(" }) {
      title = String(text[..<open]).trimmingCharacters(in: .whitespaces)
      let note = text[open...]
      owner = field("担当", in: note)
      due = field("期限", in: note)
    }
    return SummaryActionItem(title: title, owner: owner, due: due)
  }

  private static func field(_ name: String, in note: Substring) -> String? {
    guard let range = note.range(of: name) else { return nil }
    let rest = note[range.upperBound...].drop { ":： ".contains($0) }
    let value = rest.prefix { !"/／)）,、".contains($0) }
    return SummaryActionItem.normalized(String(value))
  }
}
