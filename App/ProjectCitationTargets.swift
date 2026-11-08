import Foundation

/// Which project-file citations may still be linked from an answer. A citation
/// is trusted only while its source is still readable and, when the citation
/// carries an evidence stamp, that stamp still matches. Older citations have
/// no stamp and remain valid while the source is readable.
enum ProjectCitationTargets {
  struct Evidence: Equatable {
    var isReadable: Bool
    var reference: String?
    var fingerprint: String?
  }

  /// A stamped project source is current only while its project and content
  /// fingerprint still match. A legacy reference with no stamp stays a link to
  /// the current source, not proof of the original evidence.
  static func projectFileIsCurrent(_ reference: ArtifactProjectSourceReference?,
                                   projectID: UUID?, fingerprint: String?) -> Bool {
    guard let reference else { return true }
    return reference.projectID == projectID && reference.fingerprint == fingerprint
  }

  static func live(_ citations: [ProjectCitation],
                   evidence: (UUID) -> Evidence?) -> Set<ArtifactSourceTarget> {
    var targets = Set<ArtifactSourceTarget>()
    for citation in citations {
      guard case .source(let id) = citation.target else { continue }
      guard let current = evidence(id), current.isReadable else { continue }
      if let reference = citation.evidenceReference, current.reference != reference { continue }
      if let fingerprint = citation.evidenceFingerprint, current.fingerprint != fingerprint { continue }
      targets.insert(.projectFile(id))
    }
    return targets
  }
}
