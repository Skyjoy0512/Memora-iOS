import Foundation

enum VoiceEnrollmentBuilder {
  static let maximumSamples = 3

  static func profile(results: [SpeakerAnalysisResult], qualities: [VoiceQualityMetadata], consentAt: Date) throws -> SpeakerProfile {
    guard let first = results.first, results.count == qualities.count,
          (1...maximumSamples).contains(results.count), qualities.allSatisfy(\.isValid) else {
      throw SpeakerProcessingFailure.invalidEmbedding
    }
    guard results.allSatisfy({ $0.modelID == first.modelID && $0.modelVersion == first.modelVersion }) else {
      throw SpeakerProcessingFailure.modelMismatch
    }
    let vectors = try results.map { result in
      guard result.embeddings.count == 1, let vector = result.embeddings.values.first,
            vector.count == 256, let normalized = SpeakerEmbeddingMath.mean([vector]) else {
        throw SpeakerProcessingFailure.invalidEmbedding
      }
      return normalized
    }
    guard let embedding = SpeakerEmbeddingMath.mean(vectors) else { throw SpeakerProcessingFailure.invalidEmbedding }
    let duration = qualities.reduce(0) { $0 + $1.sampleDuration }
    let energy = qualities.reduce(0) { $0 + $1.rootMeanSquare * $1.rootMeanSquare * $1.sampleDuration }
    let quality = VoiceQualityMetadata(sampleDuration: duration,
      speechDuration: qualities.reduce(0) { $0 + $1.speechDuration }, peak: qualities.map(\.peak).max() ?? 0,
      rootMeanSquare: sqrt(energy / duration), clippedSampleCount: 0, detectedSpeakerCount: 1,
      noiseAssessmentAvailable: qualities.allSatisfy(\.noiseAssessmentAvailable))
    let profile = SpeakerProfile(embeddingData: embedding, embeddingModelID: first.modelID,
      embeddingModelVersion: first.modelVersion, embeddingDimension: embedding.count,
      enrollmentDuration: duration, consentAt: consentAt, qualityMetadata: quality,
      enrollmentSamples: qualities)
    guard profile.isValid else { throw SpeakerProcessingFailure.invalidEmbedding }
    return profile
  }
}
