import Foundation

struct SpeakerEvaluationSample: Codable, Hashable, Sendable {
  enum Quality: String, Codable, Sendable {
    case approved, shortSpeech, overlappingSpeech, noisy, unreviewed
  }

  var audioID: UUID
  var enrolledSpeakerID: UUID
  var expectedSpeakerID: UUID
  var detectedSpeakerID: String
  var similarity: Double
  var recordingDevice: String
  var environment: String
  var speechDuration: TimeInterval
  var modelID: String
  var modelVersion: String
  var embeddingDimension: Int
  var consentAt: Date?
  var quality: Quality

  var isValid: Bool {
    similarity.isFinite && (-1...1).contains(similarity)
      && speechDuration.isFinite && speechDuration > 0 && embeddingDimension == 256
      && !modelID.isEmpty && !modelVersion.isEmpty && !detectedSpeakerID.isEmpty
      && !recordingDevice.isEmpty && !environment.isEmpty && consentAt != nil
  }
}
