import Foundation

struct AIRecordReference: Codable, Hashable, Sendable {
  var target: RecordPrivacyTarget
  var fingerprint: String
}
