import Foundation

enum SpeakerIdentificationService {
  static func similarities(profile: SpeakerProfile, result: SpeakerAnalysisResult) throws -> [String: Double] {
    guard profile.isEnabled else { return [:] }
    guard profile.isValid else { throw SpeakerProcessingFailure.invalidEmbedding }
    guard profile.embeddingModelID == result.modelID, profile.embeddingModelVersion == result.modelVersion else {
      throw SpeakerProcessingFailure.modelMismatch
    }
    return result.embeddings.compactMapValues {
      guard $0.count == profile.embeddingDimension else { return nil }
      return SpeakerEmbeddingMath.cosine(profile.embeddingData, $0)
    }
  }

  struct SelfMatch: Equatable, Sendable {
    let speakerID: String
    let similarity: Double
  }

  static func selfMatch(profile: SpeakerProfile, result: SpeakerAnalysisResult,
                        minimumSimilarity: Double, minimumLead: Double,
                        minimumEligibleSpeech: TimeInterval) throws -> SelfMatch? {
    guard minimumSimilarity.isFinite, minimumSimilarity > 0, minimumSimilarity <= 1,
          minimumLead.isFinite, minimumLead > 0, minimumLead <= 1,
          minimumEligibleSpeech.isFinite, minimumEligibleSpeech > 0 else {
      throw SpeakerProcessingFailure.invalidEmbedding
    }
    let scores = try similarities(profile: profile, result: result)
    guard !scores.isEmpty,
          scores.count == result.embeddings.count,
          result.embeddings.allSatisfy({ !$0.key.isEmpty && $0.value.count == profile.embeddingDimension
            && $0.value.allSatisfy(\.isFinite) }),
          scores.allSatisfy({ !$0.key.isEmpty && $0.value.isFinite && (-1...1).contains($0.value) }) else {
      return nil
    }
    // Rank every candidate before duration so a short rival can never be filtered out.
    let ranked = scores.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }
    guard let winner = ranked.first, winner.value >= minimumSimilarity else { return nil }
    guard ranked.dropFirst().allSatisfy({ winner.value - $0.value >= minimumLead }) else { return nil }
    guard let duration = result.eligibleSpeechDurations[winner.key],
          duration.isFinite, duration >= minimumEligibleSpeech,
          result.intervals.contains(where: { $0.isValid && $0.speakerID == winner.key }) else {
      return nil
    }
    return SelfMatch(speakerID: winner.key, similarity: winner.value)
  }
}
