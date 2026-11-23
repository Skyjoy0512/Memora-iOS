import Foundation

extension MemoraModel {
  func importProjectFile(_ url: URL, projectID: UUID?, importContext: LocalImportContext? = nil,
    presentsErrorsLocally: Bool = false, waitsForPreparation: Bool = true, sourceTitle: String? = nil, originalURL: URL? = nil,
    sourceMetadata: [String: String]? = nil
  ) async throws -> UUID? {
    guard let context = importContext ?? LocalImportContext(projectID: projectID, in: self),
          context.projectID == projectID, context.isCurrent(in: self) else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          bytes <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    return try await importProjectSource(title: sourceTitle ?? url.lastPathComponent, context: context, presentsErrorsLocally: presentsErrorsLocally,
      waitsForPreparation: waitsForPreparation, originalURL: originalURL, sourceMetadata: sourceMetadata) {
      try await ProjectSourceFiles.shared.copy(url)
    }
  }

  func importProjectSource(title: String, context: LocalImportContext, presentsErrorsLocally: Bool = false, waitsForPreparation: Bool = true, originalURL: URL? = nil,
    sourceMetadata: [String: String]? = nil,
    load: () async throws -> ProjectSourceFiles.Receipt?
  ) async throws -> UUID? {
    guard context.isCurrent(in: self) else { return nil }
    guard let receipt = try await load() else { return nil }
    return await addProjectFile(receipt: receipt, title: title, context: context, presentsErrorsLocally: presentsErrorsLocally, waitsForPreparation: waitsForPreparation, originalURL: originalURL, sourceMetadata: sourceMetadata)
  }

  func addProjectFile(receipt: ProjectSourceFiles.Receipt, title: String, context: LocalImportContext,
    presentsErrorsLocally: Bool = false, waitsForPreparation: Bool = true, originalURL: URL? = nil,
    sourceMetadata: [String: String]? = nil
  ) async -> UUID? {
    let projectID = context.projectID
    guard context.isCurrent(in: self) else {
      await discardProjectImportReceipt(receipt); return nil
    }
    if let existing = projectSources.first(where: { $0.projectID == projectID &&
      ($0.contentFingerprint == receipt.fingerprint || (originalURL != nil && $0.originalURL == originalURL) ||
       matchesImportedPartition($0, metadata: sourceMetadata)) }) {
      await discardProjectImportReceipt(receipt)
      return context.isCurrent(in: self) && source(id: existing.id)?.hasSameReadableEvidence(as: existing) == true ? existing.id : nil
    }
    let kind = SourceIntake.kind(for: URL(fileURLWithPath: receipt.reference))
    let value = ProjectSource(projectID: projectID, kind: kind, title: title, originalURL: originalURL,
      localFileReference: receipt.reference, contentFingerprint: receipt.fingerprint, metadata: sourceMetadata)
    let outcome = await capture(value, context: context)
    switch outcome {
    case .imported(let id):
      if waitsForPreparation { await prepareProjectSource(id) }
      else { scheduleProjectSourcePreparation(id) }
      // Once registered, the original belongs to SQLite, even if a later analysis
      // is invalidated. Never remove it or report success in a different workspace.
      guard context.isCurrent(in: self), source(id: id)?.projectID == projectID else { return nil }
      return id
    case .duplicate(let id):
      await discardProjectImportReceipt(receipt)
      guard context.isCurrent(in: self), source(id: id)?.projectID == projectID else { return nil }
      return id
    case .refused(let message):
      if presentsErrorsLocally { importErrorMessage = message }
      await discardProjectImportReceipt(receipt)
      return nil
    }
  }

  private func discardProjectImportReceipt(_ receipt: ProjectSourceFiles.Receipt) async {
    guard !projectSources.contains(where: { $0.fileReferences.contains(receipt.reference) }) else { return }
    await ProjectSourceFiles.shared.remove([receipt.reference])
  }

  private func matchesImportedPartition(_ source: ProjectSource, metadata: [String: String]?) -> Bool {
    let keys = ["partitionOriginalFingerprint", "partitionOriginalPageCount", "partitionFirstPage", "partitionLastPage"]
    return source.kind == .pdf && source.localFileReference != nil && metadata != nil && keys.allSatisfy {
      guard let value = metadata?[$0], !value.isEmpty else { return false }
      return source.metadata?[$0] == value
    }
  }
}
