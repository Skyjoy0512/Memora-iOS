import Foundation

struct SpeakerProfile: Codable, Identifiable, Hashable, Sendable {
  var id: UUID = UUID()
  var displayName = "自分"
  var isCurrentUser = true
  var embeddingData: [Float]
  var embeddingModelID: String
  var embeddingModelVersion: String
  var embeddingDimension: Int
  var enrollmentDuration: TimeInterval
  var createdAt: Date = .now
  var updatedAt: Date = .now
  var consentAt: Date
  var qualityMetadata: VoiceQualityMetadata
  var isEnabled = true
  var enrollmentSamples: [VoiceQualityMetadata]?

  var sampleCount: Int { enrollmentSamples?.count ?? 1 }

  var isValid: Bool {
    isCurrentUser && embeddingDimension == 256 && embeddingData.count == embeddingDimension
      && SpeakerEmbeddingMath.cosine(embeddingData, embeddingData) != nil
      && !embeddingModelID.isEmpty && !embeddingModelVersion.isEmpty
      && enrollmentDuration.isFinite && enrollmentDuration > 0
      && qualityMetadata.isValid
      && (enrollmentSamples.map { !$0.isEmpty && $0.allSatisfy(\.isValid) } ?? true)
  }
}
