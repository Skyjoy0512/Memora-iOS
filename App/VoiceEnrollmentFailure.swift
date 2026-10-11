import Foundation

struct VoiceEnrollmentFailure: LocalizedError {
  var sampleNumber: Int
  var reason: String

  var errorDescription: String? { "サンプル\(sampleNumber)：\(reason)" }
}
