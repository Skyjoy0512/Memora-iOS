import Foundation

/// Transient authorization for project files; never restored as an execution grant.
struct AgentSourceReference: Hashable {
  var id: UUID
  var projectID: UUID?
  var fingerprint: String
}
