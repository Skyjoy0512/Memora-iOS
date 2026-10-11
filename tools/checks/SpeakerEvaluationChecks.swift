import Foundation

@main
struct SpeakerEvaluationChecks {
  static func main() throws {
    let person = UUID()
    let other = UUID()
    func sample(_ same: Bool, _ score: Double) -> SpeakerEvaluationSample {
      SpeakerEvaluationSample(audioID: UUID(), enrolledSpeakerID: person,
        expectedSpeakerID: same ? person : other, detectedSpeakerID: "S1", similarity: score,
        recordingDevice: "synthetic", environment: "unit test", speechDuration: 10,
        modelID: "test", modelVersion: "1", embeddingDimension: 256, consentAt: .now, quality: .approved)
    }
    let samples = [sample(true, 0.9), sample(true, 0.5), sample(false, 0.8), sample(false, 0.2)]
    let report = try SpeakerEvaluation.report(samples: samples, thresholds: [0.7, 0.85])
    precondition(report.sampleCount == 4 && report.sameSpeakerCount == 2 && report.differentSpeakerCount == 2)
    precondition(report.testedThresholds[0].falseAcceptanceRate == 0.5)
    precondition(report.testedThresholds[0].falseRejectionRate == 0.5)
    precondition(report.testedThresholds[1].falseAcceptanceRate == 0)
    let oneClass = try SpeakerEvaluation.report(samples: [samples[0]], thresholds: [0.7])
    precondition(oneClass.testedThresholds[0].falseAcceptanceRate == nil)
    var excluded = samples[0]
    excluded.quality = .overlappingSpeech
    let filtered = try SpeakerEvaluation.report(samples: samples + [excluded], thresholds: [0.7])
    precondition(filtered.sampleCount == 4 && filtered.excludedCount == 1)
    var invalid = samples[0]
    invalid.consentAt = nil
    do {
      _ = try SpeakerEvaluation.report(samples: [invalid], thresholds: [0.7])
      preconditionFailure("missing consent")
    } catch SpeakerEvaluation.Failure.invalidSample { }
    invalid = samples[0]
    invalid.modelVersion = "2"
    do {
      _ = try SpeakerEvaluation.report(samples: samples + [invalid], thresholds: [0.7])
      preconditionFailure("mixed feature spaces")
    } catch SpeakerEvaluation.Failure.mixedModels { }
    let encoderData = try SpeakerEvaluation.export(samples)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let restored = try decoder.decode([SpeakerEvaluationSample].self, from: encoderData)
    precondition(restored.count == 4 && restored[0].similarity == samples[0].similarity)
    let own = SpeakerInterval(speakerID: "S1", start: 1, end: 5)
    precondition(SpeakerEmbeddingQuality.eligible(speakerID: "S1", start: 0, end: 10, intervals: [own], minimumSpeechDuration: 1))
    precondition(!SpeakerEmbeddingQuality.eligible(speakerID: "S1", start: 0, end: 1.2, intervals: [own], minimumSpeechDuration: 1))
    precondition(!SpeakerEmbeddingQuality.eligible(speakerID: "S1", start: 0, end: 10,
      intervals: [own, SpeakerInterval(speakerID: "S2", start: 2, end: 3)], minimumSpeechDuration: 1))
    precondition(SpeakerEmbeddingQuality.duration([own, own]) == 4)
    var vector = [Float](repeating: 0, count: 256)
    vector[0] = 1
    let profile = SpeakerProfile(embeddingData: vector, embeddingModelID: "test", embeddingModelVersion: "1",
      embeddingDimension: 256, enrollmentDuration: 20, consentAt: .now,
      qualityMetadata: VoiceQualityMetadata(sampleDuration: 20, speechDuration: 10, peak: 0.5,
        rootMeanSquare: 0.1, clippedSampleCount: 0, detectedSpeakerCount: 1))
    let result = SpeakerAnalysisResult(intervals: [own], embeddings: ["S1": vector],
      modelID: "test", modelVersion: "1", eligibleSpeechDurations: ["S1": 2])
    let collected = try SpeakerEvaluation.collect(profile: profile, result: result, audioID: UUID(),
      expectedSpeakers: ["S1": profile.id], device: "synthetic", environment: "unit test",
      consentAt: .now, quality: .approved)
    precondition(collected.count == 1 && collected[0].similarity == 1 && collected[0].speechDuration == 2)
    do {
      _ = try SpeakerEvaluation.collect(profile: profile, result: result, audioID: UUID(),
        expectedSpeakers: ["S1": profile.id], device: "synthetic", environment: "unit test",
        consentAt: nil, quality: .approved)
      preconditionFailure("collection without consent")
    } catch SpeakerEvaluation.Failure.missingConsent { }
    if let path = ProcessInfo.processInfo.environment["MEMORA_SYNTHETIC_EVALUATION_OUTPUT"] {
      try encoderData.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    print("SpeakerEvaluationChecks: passed (synthetic FAR/FRR, consent, compatibility, exclusions, codec)")
  }
}
