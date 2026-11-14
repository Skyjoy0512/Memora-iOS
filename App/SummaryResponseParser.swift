import Foundation

/// Splits a cloud reply into the document and the `<memora-data>` block. When
/// the block is missing or malformed, the lists and actions are read back from
/// the document itself, so a slightly off-format reply still fills the record.
enum SummaryResponseParser {
  static func parse(_ reply: String) -> MeetingSummary {
    var document = reply
    var data: DataBlock?

    if let open = reply.range(of: "<memora-data>") {
      let rest = reply[open.upperBound...]
      let close = rest.range(of: "</memora-data>")
      let json = close.map { String(rest[..<$0.lowerBound]) } ?? String(rest)
      data = decode(json)
      document = String(reply[..<open.lowerBound])
    } else if let fence = trailingJSONFence(in: reply) {
      data = decode(String(reply[fence.json]))
      document = String(reply[..<fence.whole.lowerBound])
    }

    let markdown = cleanDocument(document)
    var summary = MeetingSummary(markdown: markdown)
    if let data {
      summary.templateID = data.templateID
      summary.evidence = Array((data.sourceReferences ?? []).prefix(64))
      summary.keyPoints = cleaned(data.keyPoints)
      summary.decisions = cleaned(data.decisions)
      summary.openQuestions = cleaned(data.openQuestions)
      summary.actions = (data.actions ?? []).compactMap { item in
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = title.isEmpty ? detail : title
        guard !resolvedTitle.isEmpty else { return nil }
        return SummaryActionItem(
          title: resolvedTitle,
          detail: title.isEmpty ? "" : detail,
          owner: SummaryActionItem.normalized(item.owner),
          due: SummaryActionItem.normalized(item.due)
        )
      }
    }

    // Whatever the block did not carry is read from the document.
    let fallback = MarkdownSummaryExtractor.extract(from: markdown)
    if data?.decisions == nil { summary.decisions = fallback.decisions }
    if data?.openQuestions == nil { summary.openQuestions = fallback.openQuestions }
    if data?.actions == nil { summary.actions = fallback.actions }
    summary.actions = deduplicated(summary.actions)
    return summary
  }

  static func validateTemplate(_ summary: MeetingSummary, allowedIDs: Set<String>, actionFreeIDs: Set<String>) -> MeetingSummary {
    var result = summary
    guard let id = summary.templateID, allowedIDs.contains(id) else {
      result.templateID = nil
      result.actions = []
      result.evidence = []
      return result
    }
    if actionFreeIDs.contains(id) { result.actions = [] }
    return result
  }

  /// Drops a ```markdown fence wrapped around the whole reply.
  private static func cleanDocument(_ text: String) -> String {
    var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
    if let first = lines.first, first.hasPrefix("```") { lines.removeFirst() }
    if let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func trailingJSONFence(in text: String) -> (whole: Range<String.Index>, json: Range<String.Index>)? {
    guard let start = text.range(of: "```json", options: .backwards) else { return nil }
    let afterStart = text[start.upperBound...]
    guard let end = afterStart.range(of: "```") else { return nil }
    let json = start.upperBound..<end.lowerBound
    guard text[json].contains("\"actions\"") || text[json].contains("\"decisions\"") else { return nil }
    return (start.lowerBound..<end.upperBound, json)
  }

  private static func decode(_ json: String) -> DataBlock? {
    var body = json.trimmingCharacters(in: .whitespacesAndNewlines)
    if body.hasPrefix("```") {
      body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
      if body.hasSuffix("```") { body.removeLast(3) }
    }
    guard let first = body.firstIndex(of: "{"), let last = body.lastIndex(of: "}") else { return nil }
    return try? JSONDecoder().decode(DataBlock.self, from: Data(body[first...last].utf8))
  }

  private static func cleaned(_ items: [String]?) -> [String] {
    (items ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && SummaryActionItem.normalized($0) != nil }
  }

  /// One task per件名, so an action listed under two topics is filed once.
  static func deduplicated(_ actions: [SummaryActionItem]) -> [SummaryActionItem] {
    var seen: Set<String> = []
    return actions.filter { seen.insert(taskKey($0.title)).inserted }
  }

  /// How two task titles are compared: case, width and spacing do not matter.
  static func taskKey(_ title: String) -> String {
    let half = title.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? title
    return half.lowercased().filter { !$0.isWhitespace }
  }

  private struct DataBlock: Decodable {
    var templateID: String?
    var sourceReferences: [GeneratedSummaryEvidence]?
    var keyPoints: [String]?
    var decisions: [String]?
    var openQuestions: [String]?
    var actions: [Action]?

    struct Action: Decodable {
      var title: String?
      var detail: String?
      var owner: String?
      var due: String?
    }
  }
}

extension SummaryResponseParser {
  /// Only generation boundaries call this. Saved or user-edited Markdown is
  /// never normalized on load, render, export, or editor commit.
  static func generatedMarkdown(_ text: String) -> String {
    let withoutData = text.range(of: "<memora-data>").map { String(text[..<$0.lowerBound]) } ?? text
    let lines = withoutData.components(separatedBy: "\n")
    var protected = Set<Int>()
    var fence: Character?
    for (index, line) in lines.enumerated() {
      let value = line.trimmingCharacters(in: .whitespaces)
      if value.hasPrefix("```") || value.hasPrefix("~~~") {
        if fence == nil { fence = value.first } else if fence == value.first { fence = nil }
        protected.insert(index)
      } else if fence != nil { protected.insert(index) }
    }
    func heading(_ index: Int) -> Int? {
      guard !protected.contains(index) else { return nil }
      let line = lines[index]
      let marks = line.prefix(while: { $0 == "#" }).count
      return (1...6).contains(marks) && line.dropFirst(marks).hasPrefix(" ") ? marks : nil
    }
    func rule(_ line: String) -> Bool {
      let value = line.filter { !$0.isWhitespace }
      return value.count >= 3 && (Set(value) == ["-"] || Set(value) == ["*"] || Set(value) == ["_"])
    }
    func placeholder(_ line: String) -> Bool {
      var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if value.hasPrefix("- [ ]") || value.hasPrefix("- [x]") { value = String(value.dropFirst(5)) }
      else if value.hasPrefix("- ") || value.hasPrefix("* ") { value = String(value.dropFirst(2)) }
      value = value.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
      return ["", "なし", "記載なし", "記録なし", "未定", "該当なし", "n/a", "未指定"].contains(value.lowercased())
    }
    var omitted = Set<Int>()
    // A table with no data is scaffolding, including rows of empty cells.
    var index = 0
    while index < lines.count {
      if !protected.contains(index), lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
        let start = index
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|"), !protected.contains(index) { index += 1 }
        let range = start..<index
        let dataRows = range.dropFirst(2)
        let empty = dataRows.allSatisfy { row in
          lines[row].split(separator: "|", omittingEmptySubsequences: false).allSatisfy { placeholder(String($0)) }
        }
        if range.count >= 2, lines[start + 1].contains("---"), empty { omitted.formUnion(range) }
      } else {
        if !protected.contains(index), lines[index].trimmingCharacters(in: .whitespaces) == "- [ ]" { omitted.insert(index) }
        index += 1
      }
    }
    // Walk deepest sections first, so an empty parent cannot survive its children.
    let headings = lines.indices.filter { heading($0) != nil }
    var seen = Set<String>()
    for start in headings.reversed() {
      let depth = heading(start)!
      let end = headings.first { $0 > start && heading($0)! <= depth } ?? lines.count
      let body = (start + 1..<end).filter { !omitted.contains($0) }
      let substantive = body.contains { protected.contains($0) || (heading($0) == nil && !rule(lines[$0]) && !placeholder(lines[$0])) }
      if !substantive {
        omitted.formUnion(start..<end)
      } else {
        let identity = ([lines[start]] + body.map { lines[$0] }).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !seen.insert(identity).inserted { omitted.formUnion(start..<end) }
      }
    }
    var output: [String] = []
    var previousRule = true
    for i in lines.indices where !omitted.contains(i) {
      let line = lines[i]
      if !protected.contains(i), rule(line) {
        if !previousRule { output.append(line) }
        previousRule = true
      } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
        output.append(line)
        previousRule = false
      } else if output.last != "" { output.append("") }
    }
    while let last = output.last, last.isEmpty || rule(last) { output.removeLast() }
    return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
