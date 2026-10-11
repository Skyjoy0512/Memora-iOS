import Foundation

enum SpeakerEvaluation {
  enum Failure: Error {
    case invalidSample, mixedModels, invalidThresholds, missingConsent, noEligibleSamples
  }

  static func report(samples: [SpeakerEvaluationSample], thresholds: [Double]) throws -> SpeakerEvaluationReport {
    guard !samples.isEmpty, samples.allSatisfy(\.isValid) else { throw Failure.invalidSample }
    guard !thresholds.isEmpty, thresholds.count <= 200,
          thresholds.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { throw Failure.invalidThresholds }
    let first = samples[0]
    guard samples.allSatisfy({ $0.modelID == first.modelID && $0.modelVersion == first.modelVersion
      && $0.embeddingDimension == first.embeddingDimension }) else { throw Failure.mixedModels }
    let eligible = samples.filter { $0.quality == .approved }
    guard !eligible.isEmpty else { throw Failure.noEligibleSamples }
    let same = eligible.filter { $0.expectedSpeakerID == $0.enrolledSpeakerID }.count
    let different = eligible.count - same
    let results = Set(thresholds).sorted().map { threshold in
      var matrix = SpeakerEvaluationReport.ConfusionMatrix()
      for sample in eligible {
        let expected = sample.expectedSpeakerID == sample.enrolledSpeakerID
        let accepted = sample.similarity >= threshold
        switch (expected, accepted) {
        case (true, true): matrix.trueAcceptance += 1
        case (false, false): matrix.trueRejection += 1
        case (false, true): matrix.falseAcceptance += 1
        case (true, false): matrix.falseRejection += 1
        }
      }
      return SpeakerEvaluationReport.ThresholdResult(threshold: threshold,
        falseAcceptanceRate: different > 0 ? Double(matrix.falseAcceptance) / Double(different) : nil,
        falseRejectionRate: same > 0 ? Double(matrix.falseRejection) / Double(same) : nil, confusionMatrix: matrix)
    }
    return SpeakerEvaluationReport(sampleCount: eligible.count, excludedCount: samples.count - eligible.count,
      sameSpeakerCount: same, differentSpeakerCount: different, modelID: first.modelID,
      modelVersion: first.modelVersion, embeddingDimension: first.embeddingDimension, testedThresholds: results)
  }

  static func collect(profile: SpeakerProfile, result: SpeakerAnalysisResult, audioID: UUID,
                      expectedSpeakers: [String: UUID], device: String, environment: String,
                      consentAt: Date?, quality: SpeakerEvaluationSample.Quality) throws -> [SpeakerEvaluationSample] {
    guard let consentAt else { throw Failure.missingConsent }
    guard profile.isValid, profile.isEnabled else { throw Failure.invalidSample }
    let scores = try SpeakerIdentificationService.similarities(profile: profile, result: result)
    return scores.keys.sorted().compactMap { speaker in
      guard let expected = expectedSpeakers[speaker], let score = scores[speaker] else { return nil }
      let duration = result.eligibleSpeechDurations[speaker]
        ?? SpeakerEmbeddingQuality.duration(result.intervals.filter { $0.speakerID == speaker })
      let sample = SpeakerEvaluationSample(audioID: audioID, enrolledSpeakerID: profile.id,
        expectedSpeakerID: expected, detectedSpeakerID: speaker, similarity: score,
        recordingDevice: device, environment: environment, speechDuration: duration,
        modelID: result.modelID, modelVersion: result.modelVersion, embeddingDimension: profile.embeddingDimension,
        consentAt: consentAt, quality: quality)
      return sample.isValid ? sample : nil
    }
  }

  static func export(_ samples: [SpeakerEvaluationSample]) throws -> Data {
    guard !samples.isEmpty, samples.allSatisfy(\.isValid) else { throw Failure.invalidSample }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(samples)
  }
}
