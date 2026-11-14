import Foundation

struct SummaryArtifactScope: Sendable, Encodable {
  var ownerID: UUID
  var workspace: String
  var account: String
  var privacy: String

  var credentialHash: String
  var projectID: UUID? = nil
}
