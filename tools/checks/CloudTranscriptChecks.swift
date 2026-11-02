import Foundation

@main struct CloudTranscriptChecks {
  static func main() throws {
    let openAI = Data(#"{"text":"はい。はい。","segments":[{"start":2.1,"end":2.4,"text":"はい。"},{"start":902,"end":903,"text":"はい。"}]}"#.utf8)
    let parts = try CloudTranscriptDecoder.openAI(openAI, language: "ja")
    precondition(parts.count == 2 && parts[1].timestamp == 902 && parts[1].endTime == 903)
    precondition(parts.allSatisfy { !$0.speakerIsCertain && $0.recognitionConfidence == nil })
    precondition(parts[0].recognitionModel == "whisper-1")
    let deepgram = Data(#"{"results":{"utterances":[{"start":3,"end":4,"speaker":1,"confidence":0.6,"transcript":"いいえ"},{"start":1,"end":2,"transcript":"確認"}]}}"#.utf8)
    let diarized = try CloudTranscriptDecoder.deepgram(deepgram, language: "ja")
    precondition(diarized[0].timestamp == 1 && diarized[0].speakerID == nil)
    precondition(diarized[1].speakerID == "deepgram:1" && !diarized[1].speakerIsCertain)
    precondition(diarized[1].identificationStatus == .anonymous && diarized[1].recognitionConfidence == 0.6)
    let encoded = try JSONEncoder().encode(diarized)
    let decoded = try JSONDecoder().decode([TranscriptSegment].self, from: encoded)
    precondition(decoded == diarized)
    let old = Data("""
      {"id":"00000000-0000-0000-0000-000000000001","speaker":"話者","speakerIsCertain":false,"timestamp":1,"text":"既存の記録"}
      """.utf8)
    let restored = try JSONDecoder().decode(TranscriptSegment.self, from: old)
    precondition(restored.recognitionEngine == nil && restored.text == "既存の記録")
    for invalid in [
      #"{"text":"時刻なし"}"#,
      #"{"text":"逆転","segments":[{"start":2,"end":1,"text":"逆転"}]}"#,
      #"{"text":"負数","segments":[{"start":-1,"end":1,"text":"負数"}]}"#
    ] {
      do { _ = try CloudTranscriptDecoder.openAI(Data(invalid.utf8), language: "ja"); preconditionFailure("Invalid timing accepted") }
      catch CloudTranscriptDecoder.Failure.invalidResponse { }
    }
    for invalid in [
      #"{"results":{"channels":[{"alternatives":[{"transcript":"時刻なし"}]}]}}"#,
      #"{"results":{"utterances":[{"start":0,"end":1,"transcript":"不正","confidence":1.1}]}}"#
    ] {
      do { _ = try CloudTranscriptDecoder.deepgram(Data(invalid.utf8), language: "ja"); preconditionFailure("Invalid response accepted") }
      catch CloudTranscriptDecoder.Failure.invalidResponse { }
    }
    let silent = try CloudTranscriptDecoder.openAI(Data(#"{"text":"","segments":[]}"#.utf8), language: "ja")
    precondition(silent.isEmpty)
    print("CloudTranscriptChecks: PASS. Provider fixtures, repeated utterances, exact times, anonymous speakers, optional confidence, old/new Codable, malformed timing refusal. No external API called.")
  }
}
