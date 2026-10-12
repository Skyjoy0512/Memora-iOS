import Foundation

struct AIRecordReference: Codable, Hashable {
  var target: RecordPrivacyTarget
  var fingerprint: String
}
