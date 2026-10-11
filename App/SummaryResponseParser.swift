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
