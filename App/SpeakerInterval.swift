import Foundation

struct SpeakerInterval: Codable, Hashable, Sendable {
  var speakerID: String
  var start: TimeInterval
  var end: TimeInterval

  var isValid: Bool { !speakerID.isEmpty && start.isFinite && end.isFinite && start >= 0 && end > start }
}
