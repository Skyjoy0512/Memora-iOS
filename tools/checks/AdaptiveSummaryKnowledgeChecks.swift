import Foundation

@main
enum AdaptiveSummaryKnowledgeChecks {
  static func main() throws {
    let segment = TranscriptSegment(id: UUID(), speaker: "話者1", speakerIsCertain: false,
      timestamp: 12, text: "負荷試験で問題が見つかったため、11月20日の公開予定を再検討します。担当者は次回決めます。")
    let reference = SummaryKnowledge.Reference(sourceSegmentID: segment.id.uuidString, quote: "11月20日の公開予定を再検討します")
    let facts = SummaryKnowledge.Status.allCases.enumerated().map { index, status in
      SummaryKnowledge.Fact(id: "f\(index)", category: .owner, content: "担当について\(status.rawValue)", status: status,
        relatedTopicID: "t1", sourceReferences: [reference])
    }
    let knowledge = SummaryKnowledge(selectedProfileIDs: ["market.releaseReview", "market.sales", "forged"],
      contentType: .mixed, topics: [.init(id: "t1", title: "公開時期の再検討")], facts: facts,
      coverage: [.init(aspect: "予算", status: .notMentioned)])
    let data = try JSONEncoder().encode(knowledge)
    let decoded = try JSONDecoder().decode(SummaryKnowledge.self, from: data)
    precondition(decoded == knowledge)
    let validated = knowledge.validated(allowedProfiles: ["market.releaseReview", "market.sales"]) {
      $0.sourceSegmentID == segment.id.uuidString && segment.text.contains($0.quote)
    }
    precondition(validated.selectedProfileIDs == ["market.releaseReview", "market.sales"])
    precondition(validated.facts.map(\.status) == SummaryKnowledge.Status.allCases)
    precondition(validated.facts.filter { !$0.status.isVisible }.allSatisfy { $0.sourceReferences?.isEmpty == true })
    var forged = knowledge
    forged.facts[0].sourceReferences = [.init(sourceSegmentID: UUID().uuidString, quote: "架空の引用です。")]
    precondition(forged.validated(allowedProfiles: []) { _ in false }.facts[0].status == .uncertain)
    precondition(forged.validated(allowedProfiles: []) { _ in false }.facts[0].sourceReferences?.isEmpty == true)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object["facts"] = [42, ["id": "bad", "status": "invented"], (object["facts"] as! [[String: Any]])[0]]
    let recovered = try JSONDecoder().decode(SummaryKnowledge.self, from: JSONSerialization.data(withJSONObject: object))
    precondition(recovered.facts.count == 1, "A damaged fact cannot destroy its siblings")

    var record = Meeting(id: UUID(), title: "本人のタイトル", createdAt: .now, duration: 60, source: .recording,
      status: .ready, summary: "## 公開時期の再検討\n負荷試験の問題を確認し、公開時期を再検討する。",
      keyPoints: [], decisions: [], openQuestions: [], transcript: [segment])
    let version = TemplateSummary.snapshot(record: record, templateID: "market.releaseReview",
      preferences: SummaryPreferences(), modelInfo: "fixture", knowledge: validated)
    record.summaryVersions = [version]; record.activeSummaryVersionID = version.id
    precondition(record.currentSummaryKnowledge == validated)
    precondition(record.reusableSummaryFacts.count == 4)
    precondition(record.summaryKnowledgeText.contains(segment.id.uuidString))
    var forgedRecord = record
    forgedRecord.summaryVersions[0].knowledge!.facts[0].sourceReferences![0].quote = "原文にない引用を検出します。"
    precondition(forgedRecord.reusableSummaryFacts.count == 3)
    forgedRecord = record
    forgedRecord.summaryVersions[0].knowledge!.facts[0].speakerIDs = ["wrong-person-id"]
    precondition(forgedRecord.reusableSummaryFacts.count == 3)
    forgedRecord = record
    forgedRecord.summaryVersions[0].knowledge!.facts[0].sourceReferences = []
    precondition(forgedRecord.reusableSummaryFacts.count == 3)
    forgedRecord = record
    var invalidDuplicate = forgedRecord.summaryVersions[0].knowledge!.facts[0]
    invalidDuplicate.sourceReferences![0].quote = "原文にない引用を検出します。"
    forgedRecord.summaryVersions[0].knowledge!.facts.insert(invalidDuplicate, at: 0)
    precondition(forgedRecord.reusableSummaryFacts.count == 4, "An invalid duplicate hid its valid sibling")
    let encoded = try JSONEncoder().encode(record)
    let roundtrip = try JSONDecoder().decode(Meeting.self, from: encoded)
    precondition(roundtrip.currentSummaryKnowledge == validated && roundtrip.title == "本人のタイトル")
    var untitled = record
    untitled.title = ""
    untitled.summary = "# 公開時期の再検討\n\n検証後に判断する。"
    precondition(untitled.displayTitle == "公開時期の再検討" && untitled.title.isEmpty)
    untitled.title = "本人が付けた題"
    precondition(untitled.displayTitle == "本人が付けた題")
    var changed = record; changed.transcript[0].text += "訂正がありました。"
    precondition(changed.currentSummaryKnowledge == nil)
    changed = record; changed.summary += "本人の追記"
    precondition(changed.currentSummaryKnowledge == nil)
    changed = record; changed.decisions = ["本人が編集した決定"]
    precondition(changed.currentSummaryKnowledge == nil)
    changed = record; changed.audioURL = nil
    precondition(changed.currentSummaryKnowledge == validated, "Transcript evidence survives audio deletion")
    var legacyVersion = try JSONSerialization.jsonObject(with: JSONEncoder().encode(version)) as! [String: Any]
    legacyVersion.removeValue(forKey: "knowledge"); legacyVersion.removeValue(forKey: "sourceFingerprint")
    let old = try JSONDecoder().decode(TemplateSummary.self, from: JSONSerialization.data(withJSONObject: legacyVersion))
    precondition(old.knowledge == nil && old.markdown == version.markdown)
    legacyVersion["knowledge"] = "damaged optional enrichment"
    let damaged = try JSONDecoder().decode(TemplateSummary.self, from: JSONSerialization.data(withJSONObject: legacyVersion))
    precondition(damaged.markdown == version.markdown)
    let truncated = SummaryResponseParser.parse("## 内容\n原文の事実\n<memora-data>{\"templateID\":\"content.adaptive\",\"actions\":[")
    precondition(!truncated.hasCompleteExtraction && !truncated.markdown.contains("memora-data"))
    let badFence = SummaryResponseParser.parse("本文\n```json\n{\"actions\":[")
    precondition(!badFence.hasCompleteExtraction && badFence.markdown == "本文")
    let reply = "本文\n<memora-data>{\"templateID\":\"market.sales\",\"knowledge\":\(String(data: data, encoding: .utf8)!),\"actions\":[{\"title\":\"見積を確認\",\"owner\":null,\"due\":null}]}</memora-data>"
    let parsed = SummaryResponseParser.parse(reply)
    precondition(parsed.hasCompleteExtraction && parsed.knowledge == knowledge)
    precondition(parsed.actions.first?.owner == nil && parsed.actions.first?.due == nil)
    let id = UUID()
    precondition(MeetingSummaryInput.sourceSegmentID(sourceID: id, index: 2) == MeetingSummaryInput.sourceSegmentID(sourceID: id, index: 2))
    precondition(MeetingSummaryInput.sourceSegmentID(sourceID: id, index: 2) != MeetingSummaryInput.sourceSegmentID(sourceID: id, index: 3))
    precondition(SummaryContentProjection.supplements(["公開する"], markdown: "公開しない") == ["公開する"])
    precondition(SummaryContentProjection.supplements(["公開する"], markdown: "公開する\nという案は却下") == ["公開する"])
    precondition(SummaryContentProjection.supplements(["API_KEY_A"], markdown: "api_key_a") == ["API_KEY_A"])
    precondition(SummaryContentProjection.supplements(["[仕様](https://example.test/b)"],
      markdown: "[仕様](https://example.test/a)") == ["[仕様](https://example.test/b)"])
    precondition(SummaryContentProjection.supplements(["仕様"], markdown: "[仕様](https://example.test/a)") == ["仕様"])
    precondition(SummaryContentProjection.supplements(["予算は-100万円"], markdown: "予算は100万円") == ["予算は-100万円"])
    precondition(SummaryContentProjection.supplements(["承認後に公開する"], markdown: "## 方針\n- **承認後に公開する**").isEmpty)
    var mixed = MeetingSummary(markdown: "本文", actions: [.init(title: "実際に合意した行動")], templateID: "work.learning",
      knowledge: .init(selectedProfileIDs: ["work.learning", "market.regular"]))
    precondition(SummaryResponseParser.validateTemplate(mixed, allowedIDs: ["work.learning", "market.regular"], actionFreeIDs: ["work.learning"]).actions.count == 1)
    mixed.knowledge?.selectedProfileIDs = ["work.learning", "forged"]
    precondition(SummaryResponseParser.validateTemplate(mixed, allowedIDs: ["work.learning", "market.regular"], actionFreeIDs: ["work.learning"]).actions.isEmpty)
    var protected = record
    protected.summaryVersions[0].knowledge?.selectedProfileIDs = ["market.regular", "work.care"]
    precondition(protected.effectivePrivacy.classification == .sensitive)
    let related = knowledge.relevantFacts(to: ["担当"], excluding: "")
    precondition(related.allSatisfy { $0.status.isVisible } && related.count == 4)

    print("AdaptiveSummaryKnowledgeChecks: passed (six statuses, mixed profiles, lossy facts, real Meeting/history codec, legacy/corrupt optional data, edit invalidation, audio deletion, truncated JSON, unspecified tasks, stable source IDs). No model/network claim.")
  }
}

// Tests the real record codec without accessing personal media files.
enum MediaFiles {
  static func resolve(_ value: String) -> URL? { nil }
  static func reference(for url: URL) -> String? { nil }
  static func writePhoto(_ data: Data) -> String? { nil }
  static func deletePhoto(_ name: String) {}
}
