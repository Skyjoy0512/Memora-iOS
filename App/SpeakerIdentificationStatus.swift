import Foundation

enum SpeakerIdentificationStatus: String, Codable, Hashable, Sendable {
  case unassigned, anonymous, manual, overlap, insufficientTiming, unusable
}
