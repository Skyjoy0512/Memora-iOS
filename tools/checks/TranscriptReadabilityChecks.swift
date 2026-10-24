import Foundation

@main
struct TranscriptReadabilityChecks {
  static func main() {
    let examples = [
      ("えーと、えっと、予算は10万円ではなく12万円です。", "予算は10万円ではなく12万円です。"),
      (" あのー、10月24日までなら対応できるかもしれません。 ", "10月24日までなら対応できるかもしれません。"),
      ("Um, we cannot promise 100% uptime.", "we cannot promise 100% uptime."),
      ("ええと、佐藤さんは担当を引き受けていません。", "佐藤さんは担当を引き受けていません。"),
      ("えーと、", "えーと、"),
      ("「えーと、」という表現を残す。", "「えーと、」という表現を残す。"),
      ("あの製品はその仕様ではありません。", "あの製品はその仕様ではありません。"),
      ("はい、同意ではなく確認だけです。", "はい、同意ではなく確認だけです。"),
      ("Umberto / https://example.com/a?x=1 / 1,000円", "Umberto / https://example.com/a?x=1 / 1,000円"),
      ("えーとさんに聞きます。", "えーとさんに聞きます。"),
      ("多分、10ではなく20です。", "多分、10ではなく20です。"),
      ("A\r\n  えっと、B  ", "A\nB")
    ]
    for (source, expected) in examples {
      precondition(TranscriptReadability.cleaned(source) == expected, source)
      precondition(TranscriptReadability.cleaned(expected) == expected, "Projection is not idempotent")
    }
    let original = TranscriptSegment(id: UUID(), speaker: "Speaker 1", speakerIsCertain: false,
      timestamp: 37, text: "えーと、予定は未確定です。", endTime: 42)
    _ = TranscriptReadability.cleaned(original.text)
    let evidence = MeetingSummaryInput.cloudLine(for: original)
    precondition(evidence.contains(original.text) && evidence.contains(original.id.uuidString))
    precondition(original.timestamp == 37 && original.endTime == 42 && !original.speakerIsCertain)
    print("Transcript reading checks passed: conservative fillers, negatives/numbers/names/quotes/uncertainty, idempotence and raw evidence preservation")
  }
}
