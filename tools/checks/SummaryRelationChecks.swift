import Foundation

@main
enum SummaryRelationChecks {
  static func main() throws {
    for bullet in ["-", "*"] {
      for colon in [":", "：", ""] {
        let legacy = """
        ### サマリー
        \(bullet) **決定事項**:
          - SIDを分ける
        \(bullet) **予定アクション**\(colon)
          - 榎木さんへ報告
        ### アクションアイテム
        | タイトル | 説明 | 責任者 | 期限 |
        | --- | --- | --- | --- |
        | 榎木さんへ報告 | 遅延を共有 | Speaker 1 | 未定 |
        """
        let extracted = SummaryResponseParser.parse(legacy)
        precondition(extracted.decisions == ["SIDを分ける"])
        precondition(extracted.actions.count == 1 && extracted.actions[0].title == "榎木さんへ報告")
        precondition(extracted.actions[0].owner == "Speaker 1" && extracted.actions[0].due == nil)
        let withoutTable = SummaryResponseParser.parse(legacy.components(separatedBy: "### アクションアイテム")[0])
        precondition(withoutTable.decisions == ["SIDを分ける"])
        precondition(withoutTable.actions.map(\.title) == ["榎木さんへ報告"])
      }
    }
    let parent = "公開は延期します"
    let raw = "検証が終わっていないため、公開は延期します。"
    let source = TranscriptSegment(id: UUID(), speaker: "話者1", speakerIsCertain: false, timestamp: 12, text: raw)
    func validate(parent candidate: String? = nil, kind: String = "reason", id: String? = nil, quote: String? = nil,
                  parents: [String]? = nil, transcript: [TranscriptSegment]? = nil, duration: Double = 60) -> SummaryRelation? {
      SummaryRelation.validated(parent: candidate ?? parent, kind: kind, sourceSegmentID: id ?? source.id.uuidString,
        quote: quote ?? raw, parents: parents ?? [parent], transcript: transcript ?? [source], duration: duration)
    }
    let reason = SummaryRelation.validated(parent: parent, kind: "reason", sourceTime: "00:12", quote: raw,
      points: [], decisions: [parent], transcript: [source], duration: 60)!
    precondition(reason == validate())
    for invalid in ["00:11", "12", "[00:12]", " 00:12", "00:12 "] {
      precondition(SummaryRelation.validated(parent: parent, kind: "reason", sourceTime: invalid,
        quote: raw, points: [], decisions: [parent], transcript: [source], duration: 60) == nil)
    }
    var sameTime = source; sameTime.id = UUID(); sameTime.timestamp = 12.4
    precondition(SummaryRelation.validated(parent: parent, kind: "reason", sourceTime: "00:12",
      quote: raw, points: [], decisions: [parent], transcript: [source, sameTime], duration: 60) == nil)
    let pointRelation = SummaryRelation.validated(parent: parent, kind: "reason", sourceTime: "00:12", quote: raw,
      points: [parent], decisions: [], transcript: [source], duration: 60)!
    precondition(pointRelation.target == .point && reason.target == .decision && pointRelation != reason)
    precondition(SummaryRelationMarkdown.bullets([parent], relations: [pointRelation]) == ["- " + parent])
    precondition(SummaryRelation.validated(parent: parent, kind: "reason", sourceTime: "00:12", quote: raw,
      points: [parent], decisions: [parent], transcript: [source], duration: 60) == nil)
    precondition(reason.quote == raw && reason.sourceSegmentID == source.id && reason.kind == .reason)
    precondition(validate(id: "forged") == nil && validate(id: UUID().uuidString) == nil)
    precondition(validate(kind: "decision") == nil && validate(kind: "condition") == nil)
    precondition(validate(parent: "別の決定事項") == nil)
    precondition(validate(parents: []) == nil && validate(parents: [parent, parent]) == nil)
    precondition(validate(transcript: []) == nil && validate(transcript: [source, source]) == nil)
    precondition(validate(quote: "検証が終わったため、公開は延期します。") == nil)
    precondition(validate(quote: "検証が終わっていないため") == nil)
    precondition(validate(duration: .nan) == nil && validate(duration: .infinity) == nil && validate(duration: 11) == nil)
    for timestamp in [-1.0, Double.nan, Double.infinity] {
      var invalid = source; invalid.timestamp = timestamp
      precondition(validate(transcript: [invalid]) == nil)
    }
    var changed = source; changed.text = "変更された発言"
    precondition(validate(transcript: [changed]) == nil)
    var truncated = source; truncated.text = raw + "という提案は却下です。"
    precondition(validate(transcript: [truncated]) == nil, "Never accept a quote that cut off a rejection")
    var multiline = source; multiline.text = raw + "\n条件は未定。"
    precondition(validate(quote: multiline.text, transcript: [multiline]) == nil)
    var long = source; long.text = raw + String(repeating: "長", count: 200)
    precondition(validate(quote: long.text, transcript: [long]) == nil)
    var conditional = source; conditional.id = UUID(); conditional.text = "承認された場合だけ公開します。承認されなければ公開しません。"
    let condition = validate(parent: "公開します", kind: "condition", id: conditional.id.uuidString,
      quote: conditional.text, parents: ["公開します"], transcript: [conditional])!
    var effectSource = source; effectSource.id = UUID(); effectSource.text = "その結果、公開は延期します。"
    precondition(validate(kind: "effect", id: effectSource.id.uuidString, quote: effectSource.text, transcript: [effectSource]) != nil)
    var noCue = source; noCue.text = "先に検証し、公開は延期します。"
    precondition(validate(quote: noCue.text, transcript: [noCue]) == nil)

    let context = MeetingSummaryInput(title: "検証用・端末内要約の関係", date: Date(timeIntervalSince1970: 1_792_800_000),
      duration: 60, participantNames: [], transcript: [source], template: .builtIn(.meetingMinutes))
    let topic = SummaryTopic(title: "公開前の検証", startTime: 0, endTime: 60, points: ["検証結果は未確認です。"],
      decisions: [parent], actions: [SummaryActionItem(title: "検証結果を確認する", owner: nil, due: "来週")],
      questions: ["公開日は未定です。"], relations: [reason, reason])
    let child = "理由：「\(raw)」"
    let document = SummaryMarkdownBuilder.build(template: context.template, input: context,
      headline: context.title, overview: "公開を延期し、検証結果を確認します。", topics: [topic])
    for template in SummaryTemplate.allCases {
      let markdown = SummaryMarkdownBuilder.build(template: .builtIn(template), input: context,
        headline: context.title, overview: "検証結果は未確認です。", topics: [topic])
      precondition(markdown.contains(child))
      precondition(markdown.components(separatedBy: child).count == 2, "Duplicate evidence must not duplicate children")
      let extracted = MarkdownSummaryExtractor.extract(from: markdown)
      precondition(extracted.decisions.count == 1 && extracted.decisions[0].contains(raw))
      precondition(extracted.actions.count == 1 && extracted.actions[0].owner == nil && extracted.actions[0].due == "来週")
      precondition(!extracted.actions.contains { $0.title.contains("理由") })
      let blocks = MarkdownBlockParser.sourcedBlocks(for: markdown)
      let childBlock = blocks.first { if case .bullet(_, _, let text) = $0.block { return text == child }; return false }!
      if case .bullet(let level, _, _) = childBlock.block {
        precondition(level == 1)
      }
      let edited = MarkdownBlockWriter.replacing(childBlock, with: .bullet(level: 1,
        marker: .dot, text: "理由：編集した検証メモ"), in: markdown)
      precondition(edited.contains("  - 理由：編集した検証メモ") && edited.contains(parent))
    }
    var flat = topic; flat.relations = []
    precondition(!SummaryMarkdownBuilder.build(template: context.template, input: context,
      headline: "検証", overview: "概要", topics: [flat]).contains("理由："))
    var renamed = topic; renamed.decisions = ["変更した決定事項"]
    precondition(!SummaryMarkdownBuilder.build(template: context.template, input: context,
      headline: "検証", overview: "概要", topics: [renamed]).contains("理由："))
    let pointOnly = SummaryTopic(title: "提案の説明", startTime: 0, endTime: 10, points: [parent], relations: [pointRelation])
    let decisionOnly = SummaryTopic(title: "別の決定", startTime: 10, endTime: 60, points: ["確認した事実"], decisions: [parent])
    let separated = SummaryMarkdownBuilder.build(template: context.template, input: context,
      headline: "検証", overview: "概要", topics: [pointOnly, decisionOnly])
    precondition(separated.contains(child) && MarkdownSummaryExtractor.extract(from: separated).decisions == [parent])
    let detailed = SummaryMarkdownBuilder.build(template: .builtIn(.detailedMinutes), input: context,
      headline: "検証", overview: "概要", topics: [pointOnly, decisionOnly])
    precondition(MarkdownSummaryExtractor.extract(from: detailed).decisions == [parent])
    let conditionalLines = SummaryRelationMarkdown.bullets(["公開します"], relations: [condition]).joined(separator: "\n")
    precondition(conditionalLines.contains("承認されなければ公開しません。"))
    let notes = SummaryRelationMarkdown.overviewNotes([topic], limit: 2000)
    precondition(notes.contains(raw) && notes.contains("（決定）"))
    precondition(SummaryRelationMarkdown.overviewNotes([topic], limit: notes.count) == notes)
    precondition(SummaryRelationMarkdown.overviewNotes([topic], limit: notes.count - 1).isEmpty)
    var markup = source; markup.text = "条件が満たされた場合だけ公開します。[確認](https://invalid.example) | # 変更はしません。"
    let literal = validate(parent: "公開します", kind: "condition", quote: markup.text, parents: ["公開します"], transcript: [markup])!
    let literalLines = SummaryRelationMarkdown.bullets(["公開します"], relations: [literal])
    precondition(MarkdownBlockParser.plainText(literalLines[1].dropFirst(4).description) == "条件：「\(markup.text)」")
    precondition(MarkdownBlockParser.blocks(for: literalLines.joined(separator: "\n")).count == 2)

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("summary-relations-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("records.sqlite")
    let store = LocalStore(fileURL: url)
    try store.prepare()
    try store.write("relation-test-summary", data: JSONEncoder().encode(document))
    let reopened = LocalStore(fileURL: url)
    try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome("relation-test-summary") else { preconditionFailure("No saved summary") }
    let persisted = try JSONDecoder().decode(String.self, from: data)
    precondition(persisted == document)
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--fixture" {
      let fixture: [String: String] = ["summary": document, "raw": raw, "segmentID": source.id.uuidString,
        "parent": parent, "child": child, "kind": "production-builder-fixture"]
      try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys]).write(
        to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .withoutOverwriting)
    }
    print("Summary relation checks passed: whole-utterance evidence/parent/UUID/kind/time/window validation, conservative rejection, all built-in templates, deduplication, Markdown/edit round trip, conditions in bounded overview notes and real SQLite reopen. Model generation is not exercised.")
  }
}
