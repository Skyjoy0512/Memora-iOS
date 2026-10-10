import Foundation

struct VoiceProfile: Codable, Equatable {
  var fileName: String
  var duration: TimeInterval
  var registeredAt: Date
}
