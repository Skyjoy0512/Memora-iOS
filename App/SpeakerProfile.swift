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
}
