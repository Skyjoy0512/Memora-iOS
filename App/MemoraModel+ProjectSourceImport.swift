import Foundation

extension MemoraModel {
  func importProjectFile(_ url: URL, projectID: UUID, importContext: LocalImportContext? = nil) async throws -> UUID? {
    guard let context = importContext ?? LocalImportContext(projectID: projectID, in: self),
          context.projectID == projectID, context.isCurrent(in: self) else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          bytes <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    if ["m4a", "mp3", "wav", "aiff", "aif", "caf", "flac", "ogg"].contains(url.pathExtension.lowercased()) {
      return await importAudio(from: url, spaceID: projectID, importContext: context)
    }
    return try await importProjectSource(title: url.lastPathComponent, context: context) {
      try await ProjectSourceFiles.shared.copy(url)
    }
  }

  func importProjectSource(title: String, context: LocalImportContext,
    load: () async throws -> ProjectSourceFiles.Receipt?
  ) async throws -> UUID? {
    guard context.projectID != nil, context.isCurrent(in: self) else { return nil }
    guard let receipt = try await load() else { return nil }
    return await addProjectFile(receipt: receipt, title: title, context: context)
  }

  func addProjectFile(receipt: ProjectSourceFiles.Receipt, title: String, context: LocalImportContext) async -> UUID? {
    guard let projectID = context.projectID, context.isCurrent(in: self) else {
      await discardProjectImportReceipt(receipt); return nil
    }
    if let existing = projectSources.first(where: { $0.projectID == projectID && $0.contentFingerprint == receipt.fingerprint }) {
      await discardProjectImportReceipt(receipt)
      return context.isCurrent(in: self) && source(id: existing.id) == existing ? existing.id : nil
    }
    let suffix = (receipt.reference as NSString).pathExtension.lowercased()
    let kind: ProjectSource.Kind = suffix == "pdf" ? .pdf :
      ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif", "webp"].contains(suffix) ? .image : .document
    let value = ProjectSource(projectID: projectID, kind: kind, title: title,
      localFileReference: receipt.reference, contentFingerprint: receipt.fingerprint)
    guard storeProjectSource(value) else {
      await discardProjectImportReceipt(receipt); return nil
    }
    await prepareProjectSource(value.id)
    // Once registered, the original belongs to SQLite, even if a later analysis
    // is invalidated. Never remove it or report success in a different workspace.
    guard context.isCurrent(in: self), source(id: value.id)?.projectID == projectID else { return nil }
    return value.id
  }

  private func discardProjectImportReceipt(_ receipt: ProjectSourceFiles.Receipt) async {
    guard !projectSources.contains(where: { $0.fileReferences.contains(receipt.reference) }) else { return }
    await ProjectSourceFiles.shared.remove([receipt.reference])
  }
}
