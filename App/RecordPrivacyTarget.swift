import Foundation

enum RecordPrivacyTarget: Codable, Hashable, Sendable {
  case meeting(UUID)
  case journal(UUID)
  case task(UUID)
  case person(UUID)
}
