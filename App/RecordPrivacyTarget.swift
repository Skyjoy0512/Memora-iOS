import Foundation

enum RecordPrivacyTarget: Codable, Hashable {
  case meeting(UUID)
  case journal(UUID)
  case task(UUID)
  case person(UUID)
}
