import Foundation

/// A company's license, activated with a signed code. It gives every member
/// its plan and the team features, until it expires.
struct MemoraLicense: Codable, Hashable {
  var id: String
  var company: String
  var plan: MemoraPlan
  var seats: Int
  var expiresAt: Date

  var isExpired: Bool { expiresAt < .now }
}
