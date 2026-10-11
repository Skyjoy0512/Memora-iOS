import Foundation

enum SpeakerIdentificationService {
  static func similarities(profile: SpeakerProfile, result: SpeakerAnalysisResult) throws -> [String: Double] {
    guard profile.isEnabled else { return [:] }
    guard profile.embeddingModelID == result.modelID, profile.embeddingModelVersion == result.modelVersion else {
      throw SpeakerProcessingFailure.modelMismatch
    }
    return result.embeddings.compactMapValues {
      guard $0.count == profile.embeddingDimension else { return nil }
      return SpeakerEmbeddingMath.cosine(profile.embeddingData, $0)
    }
  }
}
