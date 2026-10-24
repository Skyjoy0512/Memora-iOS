import Foundation

@main
enum SummaryTemplateNotesChecks {
  static func main() {
    let parent = "公開します"
    let raw = "承認された場合だけ公開します。承認されなければ公開しません。"
    let source = TranscriptSegment(id: UUID(), speaker: "話者1", speakerIsCertain: false, timestamp: 12, text: raw)
    let condition = SummaryRelation.validated(parent: parent, kind: "condition", sourceTime: "00:12", quote: raw,
      points: [], decisions: [parent], transcript: [source], duration: 60)!
    let group = SummaryRelationMarkdown.groups([parent], relations: [condition, condition])
    precondition(group.count == 1 && group[0].count == 2)
    precondition(group.flatMap { $0 } == SummaryRelationMarkdown.bullets([parent], relations: [condition]))
    let block = group[0].joined(separator: "\n") + "\n"
    let topic = SummaryTopic(title: "公開条件", startTime: 0, endTime: 60, points: ["確認中の事実"],
      decisions: [parent], relations: [condition, condition])
    let original = topic
    // The first line fits with the parent alone, but not with its condition.
    // No output request may receive that unqualified parent on its own.
    let limit = block.count
    let prepared = SummaryTemplateNotes.prepare([topic], characterLimit: limit)!
    precondition(prepared.count == 1 && prepared[0].title == topic.title)
    precondition(prepared[0].chunks == ["- 確認中の事実\n", block])
    precondition(prepared[0].chunks.allSatisfy { !$0.isEmpty && $0.count <= limit })
    precondition(prepared[0].chunks[1].contains("承認されなければ公開しません。"))
    precondition(topic == original)
    precondition(SummaryTemplateNotes.prepare([topic], characterLimit: limit - 1) == nil)
    precondition(SummaryTemplateNotes.prepare([topic], characterLimit: 0) == nil)
    precondition(SummaryTemplateNotes.prepare([topic], characterLimit: -1) == nil)

    var reasonSource = source; reasonSource.id = UUID(); reasonSource.timestamp = 20
    reasonSource.text = "検証が終わったので公開します。"
    let reason = SummaryRelation.validated(parent: parent, kind: "reason", sourceTime: "00:20", quote: reasonSource.text,
      points: [], decisions: [parent], transcript: [reasonSource], duration: 60)!
    var multiple = topic; multiple.relations = [condition, reason, condition]
    let multipleBlock = SummaryRelationMarkdown.bullets([parent], relations: multiple.relations).joined(separator: "\n") + "\n"
    let multipleChunks = SummaryTemplateNotes.prepare([multiple], characterLimit: multipleBlock.count)![0].chunks
    precondition(multipleChunks == ["- 確認中の事実\n", multipleBlock])
    precondition(multipleBlock.contains(raw) && multipleBlock.contains(reasonSource.text))
    precondition(SummaryTemplateNotes.prepare([multiple], characterLimit: multipleBlock.count - 1) == nil)

    let empty = SummaryTopic(title: "空の話題", startTime: 0, endTime: 0)
    precondition(SummaryTemplateNotes.prepare([], characterLimit: 1)!.isEmpty)
    precondition(SummaryTemplateNotes.prepare([empty], characterLimit: 1)![0].chunks.isEmpty)
    var point = topic; point.points = [parent]; point.decisions = []
    point.relations = [SummaryRelation.validated(parent: parent, kind: "condition", sourceTime: "00:12", quote: raw,
      points: [parent], decisions: [], transcript: [source], duration: 60)!]
    precondition(SummaryTemplateNotes.prepare([point], characterLimit: limit)![0].chunks == [block])
    var wrongTarget = point; wrongTarget.relations = [condition]
    precondition(SummaryTemplateNotes.prepare([wrongTarget], characterLimit: limit)![0].chunks == ["- 公開します\n"])

    let action = SummaryActionItem(title: "承認を確認する", detail: "既存入力の形式を維持", owner: nil, due: "未定")
    let ordinary = SummaryTopic(title: "通常の話題", startTime: 0, endTime: 20,
      points: ["要点A", "要点B"], decisions: ["決定C"], concerns: ["懸念D"], actions: [action], questions: ["質問E"])
    let expected = "- 要点A\n- 要点B\n- 決定C\n懸念D\n質問E\n承認を確認する / 担当: 未定 / 期限: 未定\n"
    precondition(SummaryTemplateNotes.prepare([ordinary], characterLimit: expected.count)![0].chunks == [expected])
    let shortChunks = SummaryTemplateNotes.prepare([ordinary], characterLimit: 30)![0].chunks
    precondition(shortChunks.joined() == expected && shortChunks.allSatisfy { $0.count <= 30 })
    let combined = SummaryTemplateNotes.prepare([ordinary, topic, empty], characterLimit: limit)!
    precondition(combined.map(\.title) == [ordinary.title, topic.title, empty.title])
    precondition(combined[0].chunks.joined() == expected && combined[1].chunks.last == block && combined[2].chunks.isEmpty)

    var oversized = empty; oversized.questions = [String(repeating: "長", count: limit)]
    // A later invalid topic rejects the entire preparation before any template
    // session is created, rather than returning already prepared partial topics.
    precondition(SummaryTemplateNotes.prepare([ordinary, oversized], characterLimit: limit) == nil)
    var multiline = empty; multiline.concerns = ["条件が成立する場合\nだけ実行する"]
    let fullNote = multiline.concerns[0] + "\n"
    precondition(SummaryTemplateNotes.prepare([multiline], characterLimit: fullNote.count)![0].chunks == [fullNote])
    precondition(SummaryTemplateNotes.prepare([multiline], characterLimit: fullNote.count - 1) == nil)
    var unicode = empty; unicode.points = ["家族👨‍👩‍👧‍👦の確認", "か\u{3099}の確認"]
    let unicodeNotes = "- 家族👨‍👩‍👧‍👦の確認\n- か\u{3099}の確認\n"
    let unicodeChunks = SummaryTemplateNotes.prepare([unicode], characterLimit: 10)![0].chunks
    precondition(unicodeChunks.count == 2 && unicodeChunks.joined() == unicodeNotes)
    precondition(unicodeChunks.allSatisfy { $0.count <= 10 })

    // Escaping markup grows the actual model input; bound the rendered value,
    // not the shorter unescaped source count.
    var markup = source; markup.text = raw + " [確認](https://invalid.example)"
    let escaped = SummaryRelation.validated(parent: parent, kind: "condition", sourceTime: "00:12", quote: markup.text,
      points: [], decisions: [parent], transcript: [markup], duration: 60)!
    let escapedTopic = SummaryTopic(title: "引用", startTime: 0, endTime: 60, decisions: [parent], relations: [escaped])
    let escapedBlock = SummaryRelationMarkdown.bullets([parent], relations: [escaped]).joined(separator: "\n") + "\n"
    precondition(escapedBlock.contains("\\[確認\\]"))
    precondition(SummaryTemplateNotes.prepare([escapedTopic], characterLimit: escapedBlock.count)![0].chunks == [escapedBlock])
    precondition(SummaryTemplateNotes.prepare([escapedTopic], characterLimit: escapedBlock.count - 1) == nil)
    print("Summary template note checks passed: indivisible parent/condition groups, all-topic preflight, exact newline/Unicode/escape bounds, unchanged ordinary notes, ordered complete chunks and oversized-input rejection. No model/session or device execution.")
  }
}
