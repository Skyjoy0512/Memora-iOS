import Foundation

extension MemoraModel {
  func importPDFParts(_ partition: PDFSourcePartition, context: LocalImportContext) async throws -> [UUID]? {
    guard context.isCurrent(in: self) else { return nil }
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
    var copied: [String] = []
    var committed = false
    do {
      var proposals: [(part: PDFSourcePartition.Part, source: ProjectSource, isNew: Bool)] = []
      for part in partition.parts {
        try Task.checkCancellation()
        guard context.isCurrent(in: self) else {
          await discardPDFPartCopies(copied); return nil
        }
        if let existing = projectSources.first(where: {
          matchesPDFPart($0, partition: partition, part: part, projectID: context.projectID)
        }) {
          proposals.append((part, existing, false))
          continue
        }
        let receipt = try await ProjectSourceFiles.shared.copy(part.url)
        copied.append(receipt.reference)
        guard context.isCurrent(in: self) else {
          await discardPDFPartCopies(copied); return nil
        }
        let title = partition.originalName + "（元PDF \(part.firstPage)–\(part.lastPage)ページ）"
        let source = ProjectSource(projectID: context.projectID, kind: .pdf, title: title,
          localFileReference: receipt.reference, contentFingerprint: receipt.fingerprint, metadata: [
            "partitionOriginalFingerprint": partition.fingerprint,
            "partitionOriginalName": partition.originalName,
            "partitionOriginalPageCount": String(partition.originalPageCount),
            "partitionFirstPage": String(part.firstPage), "partitionLastPage": String(part.lastPage)
          ])
        proposals.append((part, source, true))
      }
      try Task.checkCancellation()
      guard context.isCurrent(in: self), isStoreWritable() else {
        await discardPDFPartCopies(copied); return nil
      }
      var added: [ProjectSource] = []
      var ids: [UUID] = []
      // Recheck deduplication after file I/O. Another import may have committed
      // the same original/range while this group was being copied.
      for proposal in proposals {
        if let existing = projectSources.first(where: {
          matchesPDFPart($0, partition: partition, part: proposal.part, projectID: context.projectID)
        }) {
          ids.append(existing.id)
        } else {
          guard proposal.isNew else { await discardPDFPartCopies(copied); return nil }
          added.append(proposal.source)
          ids.append(proposal.source.id)
        }
      }
      if !added.isEmpty {
        // A failed group write must not leave a subset registered or start AI
        // work for records that were never durably saved.
        let candidate = added + projectSources
        guard handlingPersistenceFailureLocally({ persistNow(candidate, forKey: StorageKey.projectSources) }) else {
          await discardPDFPartCopies(copied); return nil
        }
        projectSources = candidate
        invalidateProjectEvidence(added.map { .source($0.id) })
      }
      committed = true
      var preceding: Task<Void, Never>?
      for source in added { preceding = scheduleProjectSourcePreparation(source.id, after: preceding) }
      await discardPDFPartCopies(copied)
      return context.isCurrent(in: self) ? ids : nil
    } catch {
      if !committed { await discardPDFPartCopies(copied) }
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

  private func discardPDFPartCopies(_ names: [String]) async {
    let retained = Set(projectSources.flatMap(\.fileReferences))
    await ProjectSourceFiles.shared.remove(names.filter { !retained.contains($0) })
  }
}
