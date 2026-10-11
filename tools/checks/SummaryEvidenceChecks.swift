import Foundation

@main
struct SummaryEvidenceChecks {
  static func main() throws {
    let statement = "公開日を10月20日に決める"
    let original = TranscriptSegment(id: UUID(), speaker: "話者", speakerIsCertain: false, timestamp: 25,
      text: "結論として、公開日を10月20日に決める。")
    let matching = SummaryEvidence.matches(items: [statement, "**" + statement + "**。"], transcript: [original], duration: 60)
    precondition(matching[statement]?.id == original.id && matching.count == 2)
    precondition(SummaryEvidence.matches(items: [statement], transcript: [original, original], duration: 60).isEmpty)
    precondition(SummaryEvidence.matches(items: ["公開日は10月20日"], transcript: [original], duration: 60).isEmpty)
    precondition(SummaryEvidence.matches(items: ["決める", ""], transcript: [original], duration: 60).isEmpty)
    precondition(SummaryEvidence.matches(items: [statement], transcript: [original], duration: 24).isEmpty)
    precondition(SummaryEvidence.matches(items: [statement], transcript: [], duration: 60).isEmpty)
    for invalidTime in [Double.nan, .infinity, -1] {
      var invalidSegment = original
      invalidSegment.timestamp = invalidTime
      precondition(SummaryEvidence.matches(items: [statement], transcript: [invalidSegment], duration: 60).isEmpty)
      precondition(SummaryEvidence.matches(items: [statement], transcript: [original], duration: invalidTime).isEmpty)
    }
    var negative = original
    negative.text = "予算は-100万円に変更する"
    precondition(SummaryEvidence.matches(items: ["予算は100万円に変更する"], transcript: [negative], duration: 60).isEmpty)
    var latin = original
    latin.text = "Ｒｅｌｅａｓｅ version ABC"
    precondition(SummaryEvidence.matches(items: ["release version abc"], transcript: [latin], duration: 60).count == 1)
    let recordID = UUID()
    let segment = TranscriptSegment(id: UUID(), speaker: "話者B", speakerIsCertain: false,
      timestamp: 18, text: "肩くらいまで短く切ってください。前髪は残してください。", endTime: 24)
    let evidence = GeneratedSummaryEvidence(sectionTitle: "お客様の希望", sourceSegmentID: segment.id.uuidString,
      quote: "肩くらいまで短く切ってください")
    let links = SummaryEvidence.validatedLinks([evidence], sectionTitle: "お客様の希望",
      recordID: recordID, transcript: [segment], duration: 60)
    precondition(links.count == 1 && links[0].resolves(recordID: recordID, transcript: [segment], duration: 60))
    precondition(!links[0].resolves(recordID: UUID(), transcript: [segment], duration: 60))
    precondition(!links[0].resolves(recordID: recordID, transcript: [segment, segment], duration: 60))
    for duration in [Double.nan, .infinity, -1, Double(Int.max)] {
      precondition(!links[0].resolves(recordID: recordID, transcript: [segment], duration: duration))
      precondition(SummaryEvidence.validatedLinks([evidence], sectionTitle: "お客様の希望",
        recordID: recordID, transcript: [segment], duration: duration).isEmpty)
    }
    var changed = segment
    changed.text = "別の発言"
    precondition(!links[0].resolves(recordID: recordID, transcript: [changed], duration: 60))
    precondition(SummaryEvidence.validatedLinks([evidence], sectionTitle: "お客様の希望",
      recordID: recordID, transcript: [], duration: 60).isEmpty)
    var invalid = evidence
    invalid.sourceSegmentID = UUID().uuidString
    precondition(SummaryEvidence.validatedLinks([invalid], sectionTitle: "お客様の希望",
      recordID: recordID, transcript: [segment], duration: 60).isEmpty)
    invalid = evidence
    invalid.quote = "原文にない事実を書いた偽の引用です"
    precondition(SummaryEvidence.validatedLinks([invalid], sectionTitle: "お客様の希望",
      recordID: recordID, transcript: [segment], duration: 60).isEmpty)
    precondition(SummaryEvidence.validatedLinks([evidence, evidence], sectionTitle: "お客様の希望",
      recordID: recordID, transcript: [segment], duration: 60).count == 1)
    let paraphrase = "お客様は肩までのカットを希望"
    precondition(SummaryEvidence.matches(items: [paraphrase], transcript: [segment], duration: 60).isEmpty)
    let section = SummarySection(title: "お客様の希望", content: paraphrase, order: 0,
      sourceReferences: [segment.id], evidenceLinks: links)
    let data = try JSONEncoder().encode(section)
    let decoded = try JSONDecoder().decode(SummarySection.self, from: data)
    precondition(decoded == section)
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    legacy.removeValue(forKey: "evidenceLinks")
    let old = try JSONDecoder().decode(SummarySection.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.evidenceLinks == nil && old.sourceReferences == [segment.id])
    print("SummaryEvidenceChecks: passed (paraphrase, foreign/missing ID, changed text, quote, legacy codec)")
  }
}
