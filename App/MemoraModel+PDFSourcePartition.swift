import Foundation

extension MemoraModel {
  func recoverPendingPDFCopies() async {
    guard !isStoreProtected, !isRestoring else { return }
    try? await PDFSourceCopyJournal(store: localStore).recover()
  }

  func importPDFParts(_ partition: PDFSourcePartition, context: LocalImportContext,
    originalSource: ProjectSource? = nil
  ) async throws -> [UUID]? {
    func isCurrent() -> Bool {
      guard context.isCurrent(in: self) else { return false }
      guard let originalSource else { return true }
      return originalSource.projectID == context.projectID && originalSource.kind == .pdf &&
        source(id: originalSource.id)?.hasSameReadableEvidence(as: originalSource) == true &&
        source(id: originalSource.id)?.summaryOptions == originalSource.summaryOptions &&
        (originalSource.contentFingerprint == nil || originalSource.contentFingerprint == partition.fingerprint)
    }
    guard isCurrent() else { return nil }
    guard !partition.parts.isEmpty, partition.parts.count <= 100,
          partition.parts.first?.firstPage == 1,
          partition.parts.last?.lastPage == partition.originalPageCount else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
    var nextPage = 1
    for part in partition.parts {
      guard part.firstPage == nextPage, part.lastPage >= part.firstPage else { throw ProjectSourceFiles.Failure.invalidFile }
      nextPage = part.lastPage + 1
    }
    let journal = PDFSourceCopyJournal(store: localStore)
    try await journal.recover()
    guard isCurrent() else { return nil }
    let lease = try journal.begin(count: partition.parts.count)
    do {
      var proposals: [(part: PDFSourcePartition.Part, source: ProjectSource, isNew: Bool)] = []
      for (partIndex, part) in partition.parts.enumerated() {
        try Task.checkCancellation()
        guard isCurrent() else {
          try? await journal.finish(lease); return nil
        }
        if let existing = projectSources.first(where: {
          matchesPDFPart($0, partition: partition, part: part, projectID: context.projectID)
        }) {
          if let originalSource, existing.privacy != originalSource.privacy {
            throw PDFSourcePartitionImportFailure.privacyChanged
          }
          proposals.append((part, existing, false))
          continue
        }
        let receipt = try await ProjectSourceFiles.shared.copy(part.url, named: lease.references[partIndex])
        guard isCurrent() else {
          try? await journal.finish(lease); return nil
        }
        let originalName = originalSource?.title ?? partition.originalName
        let title = originalName + "（元PDF \(part.firstPage)–\(part.lastPage)ページ）"
        let source = ProjectSource(projectID: context.projectID, kind: .pdf, title: title,
          localFileReference: receipt.reference, contentFingerprint: receipt.fingerprint,
          privacy: originalSource?.privacy ?? RecordPrivacy(), metadata: [
            "partitionOriginalFingerprint": partition.fingerprint,
            "partitionOriginalName": originalName,
            "partitionOriginalPageCount": String(partition.originalPageCount),
            "partitionFirstPage": String(part.firstPage), "partitionLastPage": String(part.lastPage)
          ], summaryOptions: originalSource?.summaryOptions)
        proposals.append((part, source, true))
      }
      try Task.checkCancellation()
      guard isCurrent(), isStoreWritable() else {
        try? await journal.finish(lease); return nil
      }
      var added: [ProjectSource] = []
      var ids: [UUID] = []
      // Recheck deduplication after file I/O. Another import may have committed
      // the same original/range while this group was being copied.
      for proposal in proposals {
        if let existing = projectSources.first(where: {
          matchesPDFPart($0, partition: partition, part: proposal.part, projectID: context.projectID)
        }) {
          if let originalSource, existing.privacy != originalSource.privacy {
            throw PDFSourcePartitionImportFailure.privacyChanged
          }
          ids.append(existing.id)
        } else {
          guard proposal.isNew else { try? await journal.finish(lease); return nil }
          added.append(proposal.source)
          ids.append(proposal.source.id)
        }
      }
      if !added.isEmpty {
        // A failed group write must not leave a subset registered or start AI
        // work for records that were never durably saved.
        let candidate = added + projectSources
        guard handlingPersistenceFailureLocally({ persistBatch {
          [(key: StorageKey.projectSources, data: try JSONEncoder().encode(candidate)),
           try journal.committedDocument(lease, retaining: Set(added.flatMap(\.fileReferences)))]
        } }) else {
          try? await journal.finish(lease); return nil
        }
        projectSources = candidate
        invalidateProjectEvidence(added.map { .source($0.id) })
      }
      var preceding: Task<Void, Never>?
      for source in added { preceding = scheduleProjectSourcePreparation(source.id, after: preceding) }
      try? await journal.finish(lease)
      return isCurrent() ? ids : nil
    } catch {
      try? await journal.finish(lease)
      throw error
    }
  }

  private func matchesPDFPart(_ source: ProjectSource, partition: PDFSourcePartition,
    part: PDFSourcePartition.Part, projectID: UUID?
  ) -> Bool {
    source.projectID == projectID && source.kind == .pdf && source.localFileReference != nil &&
      source.metadata?["partitionOriginalFingerprint"] == partition.fingerprint &&
      source.metadata?["partitionOriginalPageCount"] == String(partition.originalPageCount) &&
      source.metadata?["partitionFirstPage"] == String(part.firstPage) &&
      source.metadata?["partitionLastPage"] == String(part.lastPage)
  }

}
