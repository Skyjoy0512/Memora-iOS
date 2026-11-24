import Foundation

@main struct CloudTranscriptChecks {
  static func main() throws {
    let openAI = Data(#"{"text":"はい。はい。","segments":[{"start":2.1,"end":2.4,"text":"はい。"},{"start":902,"end":903,"text":"はい。"}]}"#.utf8)
    let parts = try CloudTranscriptDecoder.openAI(openAI, language: "ja")
    precondition(parts.count == 2 && parts[1].timestamp == 902 && parts[1].endTime == 903)
    precondition(parts.allSatisfy { !$0.speakerIsCertain && $0.recognitionConfidence == nil })
    precondition(parts[0].recognitionModel == "whisper-1")
    let silence = try CloudTranscriptDecoder.openAI(Data("""
      {"text":"はい。","segments":[
        {"start":0,"end":1,"text":"無音","no_speech_prob":0.9,"avg_logprob":-2.0},
        {"start":1,"end":2,"text":"発話","no_speech_prob":0.9,"avg_logprob":-0.2}
      ]}
      """.utf8), language: "ja")
    precondition(silence.count == 1 && silence[0].text == "発話")
    let partialScores = try CloudTranscriptDecoder.openAI(Data("""
      {"text":"はい。","segments":[
        {"start":0,"end":1,"text":"採点なし"},
        {"start":1,"end":2,"text":"無音確率のみ","no_speech_prob":0.9},
        {"start":2,"end":3,"text":"対数確率のみ","avg_logprob":-2.0},
        {"start":3,"end":4,"text":"null値","no_speech_prob":null,"avg_logprob":null}
      ]}
      """.utf8), language: "ja")
    let partialTexts = ["採点なし", "無音確率のみ", "対数確率のみ", "null値"]
    precondition(partialScores.map(\.text) == partialTexts)
    let thresholds = try CloudTranscriptDecoder.openAI(Data("""
      {"text":"はい。","segments":[
        {"start":0,"end":1,"text":"無音確率しきい値","no_speech_prob":0.6,"avg_logprob":-2.0},
        {"start":1,"end":2,"text":"無音確率未満","no_speech_prob":0.5,"avg_logprob":-2.0},
        {"start":2,"end":3,"text":"対数確率しきい値","no_speech_prob":0.9,"avg_logprob":-1.0},
        {"start":3,"end":4,"text":"しきい値超え","no_speech_prob":0.61,"avg_logprob":-1.01}
      ]}
      """.utf8), language: "ja")
    let thresholdTexts = ["無音確率しきい値", "無音確率未満", "対数確率しきい値"]
    precondition(thresholds.map(\.text) == thresholdTexts)
    let outOfRange = try CloudTranscriptDecoder.openAI(Data("""
      {"text":"はい。","segments":[
        {"start":0,"end":1,"text":"確率過大","no_speech_prob":1.2,"avg_logprob":-2.0},
        {"start":1,"end":2,"text":"確率負数","no_speech_prob":-0.1,"avg_logprob":-2.0},
        {"start":2,"end":3,"text":"確率極大","no_speech_prob":1e308,"avg_logprob":-2.0}
      ]}
      """.utf8), language: "ja")
    precondition(outOfRange.map(\.text) == ["確率過大", "確率負数", "確率極大"])
    let nonFinite = Data("""
      {"text":"はい。","segments":[
        {"start":0,"end":1,"text":"非有限な無音確率","no_speech_prob":1e400,"avg_logprob":-2.0}
      ]}
      """.utf8)
    do {
      let decoded = try CloudTranscriptDecoder.openAI(nonFinite, language: "ja")
      precondition(decoded.count == 1 && decoded[0].text == "非有限な無音確率")
    } catch is DecodingError {
      // JSON cannot spell NaN or infinity; refusing the overflowing literal is
      // the decoder-supported outcome and still keeps it out of the silence path.
    }
    for missing in [
      #"{"text":"必須","segments":[{"start":0,"end":1,"no_speech_prob":0.9,"avg_logprob":-2.0}]}"#,
      #"{"text":"必須","segments":[{"text":"開始なし","end":1,"no_speech_prob":0.9,"avg_logprob":-2.0}]}"#,
      #"{"text":"必須","segments":[{"start":0,"text":"終了なし","no_speech_prob":0.9,"avg_logprob":-2.0}]}"#
    ] {
      do {
        _ = try CloudTranscriptDecoder.openAI(Data(missing.utf8), language: "ja")
        preconditionFailure("Missing required OpenAI field accepted")
      } catch is DecodingError { }
    }
    for invalid in [
      #"{"text":"逆転","segments":[{"start":2,"end":1,"text":"逆転","no_speech_prob":0.9,"avg_logprob":-2.0}]}"#,
      #"{"text":"負数","segments":[{"start":-1,"end":1,"text":"負数","no_speech_prob":0.9,"avg_logprob":-2.0}]}"#
    ] {
      do {
        _ = try CloudTranscriptDecoder.openAI(Data(invalid.utf8), language: "ja")
        preconditionFailure("Silence scores hid invalid timing")
      } catch CloudTranscriptDecoder.Failure.invalidResponse { }
    }
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
    print("CloudTranscriptChecks: PASS. Provider fixtures, repeated utterances, exact times, anonymous speakers, optional confidence, required fields, Whisper silence scores, legacy Codable, malformed timing refusal. No external API called.")
  }
}
