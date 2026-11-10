import Foundation

/// The exact saved draft bytes, retained locally before repairing their format.
struct ComposerDraftRecoveryArchive: Codable, Sendable {
  var version = 1
  var reference: Reference
  var fields: [String: Data]

  struct Reference: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var createdAt = Date.now
  }
}
