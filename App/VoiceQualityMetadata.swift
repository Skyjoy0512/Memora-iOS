import Foundation

struct VoiceQualityMetadata: Codable, Hashable, Sendable {
  var sampleDuration: TimeInterval
  var speechDuration: TimeInterval
  var peak: Float
  var rootMeanSquare: Double
  var clippedSampleCount: Int
  var detectedSpeakerCount: Int
  var noiseAssessmentAvailable = false

  var isValid: Bool {
    sampleDuration.isFinite && sampleDuration > 0 && speechDuration.isFinite
      && speechDuration > 0 && speechDuration <= sampleDuration
      && peak.isFinite && peak > 0 && peak <= 1
      && rootMeanSquare.isFinite && rootMeanSquare > 0 && rootMeanSquare <= Double(peak)
      && clippedSampleCount == 0 && detectedSpeakerCount == 1
  }
}
