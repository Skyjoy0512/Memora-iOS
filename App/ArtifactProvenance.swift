import Foundation

/// Attribution at generation time, never an access or execution grant.
struct ArtifactProvenance: Codable, Hashable, Sendable {
  var workspaceID: String?
  var sourceMessageID: UUID?
  var capturedAt = Date.now
  var records: [AIRecordReference] = []
  var projectSources: [ArtifactProjectSourceReference] = []
  var isComplete = false

  var isValid: Bool {
    records.count <= 256 && projectSources.count <= 32
      && Set(records.map(\.target)).count == records.count
      && Set(projectSources.map(\.id)).count == projectSources.count
      && (workspaceID?.utf8.count ?? 0) <= 256 && capturedAt.timeIntervalSince1970.isFinite
      && (records.map(\.fingerprint) + projectSources.map(\.fingerprint)).allSatisfy { value in
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
      }
  }
}
