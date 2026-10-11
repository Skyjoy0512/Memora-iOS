import Foundation

struct SpeakerAnalysisResult: Sendable {
  var intervals: [SpeakerInterval]
  var embeddings: [String: [Float]]
  var modelID: String
  var modelVersion: String
  var eligibleSpeechDurations: [String: TimeInterval] = [:]
}
