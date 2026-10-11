import Foundation

struct VoiceQualityMetadata: Codable, Hashable, Sendable {
  var sampleDuration: TimeInterval
  var speechDuration: TimeInterval
  var peak: Float
  var rootMeanSquare: Double
  var clippedSampleCount: Int
  var detectedSpeakerCount: Int
  var noiseAssessmentAvailable = false
}
