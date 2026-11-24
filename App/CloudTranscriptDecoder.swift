import Foundation

/// Only provider-reported times become seek targets. Anonymous speaker labels
/// identify clusters within one response, never a known person.
enum CloudTranscriptDecoder {
  enum Failure: Error { case invalidResponse }

  static func openAI(_ data: Data, language: String) throws -> [TranscriptSegment] {
    let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
    guard let parts = response.segments else {
      if response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
      throw Failure.invalidResponse
    }
    return try parts.compactMap { part in
      guard let validated = try segment(text: part.text, start: part.start, end: part.end,
                                        speaker: nil, confidence: nil, engine: "openAI",
                                        model: "whisper-1", language: language) else { return nil }
      guard !isSilence(noSpeechProbability: part.noSpeechProbability,
                       averageLogProbability: part.averageLogProbability) else { return nil }
      return validated
    }
  }

  /// Whisper reports both scores per segment; either alone is too noisy to drop
  /// speech, so only a segment past both thresholds is treated as silence.
  private static func isSilence(noSpeechProbability: Double?,
                                averageLogProbability: Double?) -> Bool {
    guard let noSpeechProbability, let averageLogProbability,
          noSpeechProbability.isFinite, averageLogProbability.isFinite,
          (0...1).contains(noSpeechProbability),
          noSpeechProbability > 0.6, averageLogProbability < -1.0 else { return false }
    return true
  }

  static func deepgram(_ data: Data, language: String) throws -> [TranscriptSegment] {
    let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
    guard let parts = response.results.utterances else {
      if response.results.channels?.first?.alternatives.first?.transcript
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { return [] }
      throw Failure.invalidResponse
    }
    return try parts.compactMap { part in
      try segment(text: part.transcript, start: part.start, end: part.end, speaker: part.speaker,
        confidence: part.confidence, engine: "deepgram", model: "nova-3", language: language)
    }.sorted { $0.timestamp < $1.timestamp }
  }

  private static func segment(text: String, start: Double, end: Double, speaker: Int?,
                              confidence: Double?, engine: String, model: String,
                              language: String) throws -> TranscriptSegment? {
    guard start.isFinite, end.isFinite, start >= 0, end >= start,
          speaker.map({ (0..<1_000).contains($0) }) ?? true,
          confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
      throw Failure.invalidResponse
    }
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    return TranscriptSegment(id: UUID(), speaker: speaker.map { "話者\($0 + 1)" } ?? "話者",
      speakerIsCertain: false, timestamp: start, text: text, endTime: end,
      speakerID: speaker.map { "deepgram:\($0)" },
      identificationStatus: speaker == nil ? .unassigned : .anonymous,
      recognitionEngine: engine, recognitionModel: model, recognitionLanguage: language,
      recognitionConfidence: confidence)
  }

  private struct OpenAIResponse: Decodable {
    var text: String
    var segments: [Part]?
    struct Part: Decodable {
      var text: String
      var start: Double
      var end: Double
      var noSpeechProbability: Double?
      var averageLogProbability: Double?

      private enum CodingKeys: String, CodingKey {
        case text, start, end
        case noSpeechProbability = "no_speech_prob"
        case averageLogProbability = "avg_logprob"
      }
    }
  }

  private struct DeepgramResponse: Decodable {
    var results: Results
    struct Results: Decodable {
      var utterances: [Utterance]?
      var channels: [Channel]?
      struct Channel: Decodable {
        var alternatives: [Alternative]
        struct Alternative: Decodable { var transcript: String }
      }
    }
    struct Utterance: Decodable {
      var transcript: String
      var start: Double
      var end: Double
      var speaker: Int?
      var confidence: Double?
    }
  }
}
