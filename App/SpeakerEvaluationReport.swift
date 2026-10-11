import Foundation

struct SpeakerEvaluationReport: Codable, Sendable {
  struct ConfusionMatrix: Codable, Sendable {
    var trueAcceptance = 0
    var trueRejection = 0
    var falseAcceptance = 0
    var falseRejection = 0
  }

  struct ThresholdResult: Codable, Sendable {
    var threshold: Double
    var falseAcceptanceRate: Double?
    var falseRejectionRate: Double?
    var confusionMatrix: ConfusionMatrix
  }

  var sampleCount: Int
  var excludedCount: Int
  var sameSpeakerCount: Int
  var differentSpeakerCount: Int
  var modelID: String
  var modelVersion: String
  var embeddingDimension: Int
  var testedThresholds: [ThresholdResult]
}
