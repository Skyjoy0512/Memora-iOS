import Foundation

struct SpeakerProfileReference: Codable, Hashable {
  var id: UUID
  var modelID: String
  var modelVersion: String
  var isEnabled: Bool
  var updatedAt: Date

  init(_ profile: SpeakerProfile) {
    id = profile.id
    modelID = profile.embeddingModelID
    modelVersion = profile.embeddingModelVersion
    isEnabled = profile.isEnabled
    updatedAt = profile.updatedAt
  }
}
