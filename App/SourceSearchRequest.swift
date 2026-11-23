import Foundation

/// Identifies a source search without holding the sources themselves. The
/// fingerprint covers only what a global or project-scoped search can read, so
/// editing metadata or timestamps does not start another search.
struct SourceSearchRequest: Hashable {
  var query: String
  var sourceFingerprint: Int
  var sourceCount: Int
  var workspaceGeneration: UUID

  var hasSources: Bool { sourceCount > 0 }

  static func make(query: String, sources: [ProjectSource], workspaceGeneration: UUID) -> SourceSearchRequest {
    var hasher = Hasher()
    for source in sources {
      hasher.combine(source.id)
      hasher.combine(source.projectID)
      hasher.combine(source.kind)
      hasher.combine(source.title)
      hasher.combine(source.summary)
      hasher.combine(source.originalURL)
      hasher.combine(source.localFileReference)
      hasher.combine(source.extractedTextReference)
      hasher.combine(source.contentFingerprint)
      hasher.combine(source.processingStatus)
      hasher.combine(source.textCoverage)
      // Privacy equality includes its revision timestamp, the same value the
      // stale-evidence guard reads; hashing only the flags could leave a
      // rejected match uncorrected under an unchanged request identity.
      hasher.combine(source.privacy)
      hasher.combine(source.errorInformation)
    }
    return SourceSearchRequest(query: query, sourceFingerprint: hasher.finalize(),
      sourceCount: sources.count, workspaceGeneration: workspaceGeneration)
  }
}
