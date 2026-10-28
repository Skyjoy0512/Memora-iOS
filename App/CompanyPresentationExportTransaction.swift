import Foundation

/// File creation can suspend; publishing the reference must remain synchronous.
@MainActor enum CompanyPresentationExportTransaction {
  static func run(
    isCurrent: () -> Bool,
    prepare: () async throws -> MemoraDocument,
    commit: (MemoraDocument) throws -> MemoraDocument,
    discard: (String) async -> Void
  ) async throws -> MemoraDocument {
    try Task.checkCancellation()
    guard isCurrent() else { throw CompanyPresentationExportError.stale }
    let prepared = try await prepare()
    do {
      try Task.checkCancellation()
      guard isCurrent() else { throw CompanyPresentationExportError.stale }
      return try commit(prepared)
    } catch {
      if let name = prepared.artifactFileReference { await discard(name) }
      throw error
    }
  }
}
