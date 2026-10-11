import Foundation

@main
struct SummaryEvidenceChecks {
  static func main() {
    let statement = "公開日を10月20日に決める"
    let segment = TranscriptSegment(id: UUID(), speaker: "話者", speakerIsCertain: false, timestamp: 25,
      text: "結論として、公開日を10月20日に決める。")
    let result = SummaryEvidence.matches(items: [statement, "**" + statement + "**。"], transcript: [segment], duration: 60)
    precondition(result[statement]?.id == segment.id && result.count == 2)
    precondition(SummaryEvidence.matches(items: [statement], transcript: [segment, segment], duration: 60).isEmpty)
    precondition(SummaryEvidence.matches(items: ["公開日は10月20日"], transcript: [segment], duration: 60).isEmpty)
    precondition(SummaryEvidence.matches(items: ["決める", ""], transcript: [segment], duration: 60).isEmpty)
    precondition(SummaryEvidence.matches(items: [statement], transcript: [segment], duration: 24).isEmpty)
    precondition(SummaryEvidence.matches(items: [statement], transcript: [], duration: 60).isEmpty)
    for invalid in [Double.nan, .infinity, -1] {
      var invalidSegment = segment
      invalidSegment.timestamp = invalid
      precondition(SummaryEvidence.matches(items: [statement], transcript: [invalidSegment], duration: 60).isEmpty)
      precondition(SummaryEvidence.matches(items: [statement], transcript: [segment], duration: invalid).isEmpty)
    }
    var negative = segment
    negative.text = "予算は-100万円に変更する"
    precondition(SummaryEvidence.matches(items: ["予算は100万円に変更する"], transcript: [negative], duration: 60).isEmpty)
    var latin = segment
    latin.text = "Ｒｅｌｅａｓｅ version ABC"
    precondition(SummaryEvidence.matches(items: ["release version abc"], transcript: [latin], duration: 60).count == 1)
    print("Summary evidence checks passed")
  }
}
