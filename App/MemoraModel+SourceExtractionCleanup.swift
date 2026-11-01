import Foundation

extension MemoraModel {
  func discardSourceExtraction(for source: ProjectSource) {
    let revisions = source.revisions ?? []
    let fingerprints = Set(([source.contentFingerprint] + revisions.map(\.fingerprint)).compactMap { $0 })
    // Old URL snapshots have no stored file digest. Drop completed derived
    // results without interrupting another source's active local extraction.
    let hasUnknownOriginal = source.contentFingerprint == nil || revisions.contains { $0.fingerprint == nil }
    Task {
      if hasUnknownOriginal { await SourceExtractionCache.shared.clearStoredResults() }
      else { await SourceExtractionCache.shared.invalidate(fingerprints: fingerprints) }
    }
  }
}
