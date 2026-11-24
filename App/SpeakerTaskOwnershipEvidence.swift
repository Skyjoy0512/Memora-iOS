import Foundation

/// A local candidate that ties one anonymous diarization cluster to the
/// registered voice. It can support task ownership, but it is never an identity.
struct SpeakerTaskOwnershipEvidence: Codable, Equatable, Sendable {
  static let storageKey = "memora.speakerTaskOwnershipEvidence.v1"
  static let maximumEntries = 256

  var recordID: UUID
  var speakerID: String
  var profileID: UUID
  var profileUpdatedAt: Date
  var transcriptFingerprint: String
  var similarity: Double

  func matches(recordID: UUID, profile: SpeakerProfile,
               transcriptFingerprint: String,
               minimumSimilarity: Double) -> Bool {
    let storedSpeakerID = speakerID.trimmingCharacters(in: .whitespacesAndNewlines)
    let storedFingerprint = self.transcriptFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    let currentFingerprint = transcriptFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard self.recordID == recordID,
          !storedSpeakerID.isEmpty,
          profileID == profile.id,
          profileUpdatedAt == profile.updatedAt,
          profile.isEnabled, profile.isValid,
          !storedFingerprint.isEmpty,
          !currentFingerprint.isEmpty,
          self.transcriptFingerprint == transcriptFingerprint,
          similarity.isFinite, (0...1).contains(similarity),
          minimumSimilarity.isFinite, (0...1).contains(minimumSimilarity),
          similarity >= minimumSimilarity else { return false }
    return true
  }
}
