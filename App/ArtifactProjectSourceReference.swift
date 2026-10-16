import Foundation

struct ArtifactProjectSourceReference: Codable, Hashable, Sendable {
  var id: UUID
  var projectID: UUID?
  var fingerprint: String
}
