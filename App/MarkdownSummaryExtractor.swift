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
    var parentIndent: Int?

    for rawLine in markdown.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespaces)

      if line.hasPrefix("#") {
        section = Section(heading: line)
        tableHeader = nil
        parentIndent = nil
        continue
      }
      // A bold label inside a bullet ("- **決定事項**:") opens a sub-section.
      if let label = boldLabel(in: line) {
        section = Section(heading: label)
        parentIndent = nil
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
      let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
      // Explicit child reasons/conditions qualify their parent, not a new
      // decision or task. Keep their actual words, without inferring causation.
      let plain = item.replacingOccurrences(of: "**", with: "")
      let isRelation = ["理由", "条件", "影響", "そのため"].contains { plain.hasPrefix($0 + "：") || plain.hasPrefix($0 + ":") }
      if let parentIndent, indent > parentIndent, isRelation {
        switch section {
        case .decisions where !result.decisions.isEmpty:
          result.decisions[result.decisions.count - 1] += " ／ " + item
          continue
        case .questions where !result.openQuestions.isEmpty:
          result.openQuestions[result.openQuestions.count - 1] += " ／ " + item
          continue
        case .actions where !bulletActions.isEmpty:
          let index = bulletActions.count - 1
          bulletActions[index].detail = [bulletActions[index].detail, item].filter { !$0.isEmpty }.joined(separator: " ／ ")
          continue
        default: break
        }
      }
      parentIndent = indent
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
      // Question labels take precedence over the word 決定 inside 未決定.
      if heading.contains("未決") || heading.contains("オープンクエスチョン") || heading.contains("未解決")
        || heading.contains("確認が必要") || heading.contains("まだ決まって") {
        self = .questions
      } else if heading.contains("決定") || heading.contains("決まったこと") || heading.contains("約束したこと") {
        self = .decisions
      } else if heading.contains("アクション") || heading.contains("今後の予定")
        || heading.contains("次にやること") || heading.contains("次にすること") {
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
    let label = String(body[..<end.lowerBound])
    // A fully bold decision is content, not a new section. Older documents
    // also used a few exact section labels without a colon.
    let sectionLabels = ["決定事項", "主要な決定事項", "決まったこと", "約束したこと", "未決事項", "未決定事項", "未解決事項", "確認が必要なこと", "まだ決まっていないこと", "オープンクエスチョン", "アクション", "アクションアイテム", "今後の予定", "次にやること", "次にすること"]
    let topicLabels = ["関与者", "要点", "課題・懸念"]
    guard (rest == ":" || rest == "：" || rest.isEmpty),
          sectionLabels.contains(label) || topicLabels.contains(label) else { return nil }
    return label
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
