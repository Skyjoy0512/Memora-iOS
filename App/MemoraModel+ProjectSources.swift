import Foundation

extension MemoraModel {
  @discardableResult
  func addProjectLink(_ input: String, projectID: UUID) throws -> UUID? {
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
          space(id: projectID) != nil else { return nil }
    let link = try ProjectSourceURL.normalized(input)
    if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
      return existing.id
    }
    var source = ProjectSource(projectID: projectID, kind: link.kind,
      title: link.youtubeID.map { "YouTube · \($0)" } ?? link.url.host ?? "Webリンク", originalURL: link.url)
    if source.kind == .web { source.processingStatus = .unavailable }
    guard storeProjectSource(source) else { return nil }
    let generation = aiWorkspaceGeneration
    if source.kind == .youtube {
      Task {
        guard aiWorkspaceGeneration == generation else { return }
        await prepareProjectSource(source.id)
      }
    }
    return source.id
  }

  func importProjectFile(_ url: URL, projectID: UUID) async throws -> UUID? {
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, space(id: projectID) != nil else { return nil }
    let workspaceID = currentTeamID
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          bytes <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    if ["m4a", "mp3", "wav", "aiff", "aif", "caf", "flac", "ogg"].contains(url.pathExtension.lowercased()) {
      guard !isImporting else { return nil }
      let existing = Set(meetings.map(\.id))
      await importAudio(from: url, spaceID: projectID)
      guard !Task.isCancelled, currentTeamID == workspaceID, !isRestoring, !isStoreProtected else { return nil }
      return meetings.first { !existing.contains($0.id) && $0.spaceID == projectID }?.id
    }
    let receipt = try await ProjectSourceFiles.shared.copy(url)
    guard !Task.isCancelled, currentTeamID == workspaceID, !isRestoring, !isStoreProtected,
          space(id: projectID) != nil else {
      await ProjectSourceFiles.shared.remove([receipt.reference]); return nil
    }
    return await addProjectFile(receipt: receipt, title: url.lastPathComponent, projectID: projectID)
  }

  func addProjectFile(receipt: ProjectSourceFiles.Receipt, title: String, projectID: UUID) async -> UUID? {
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, space(id: projectID) != nil else {
      await ProjectSourceFiles.shared.remove([receipt.reference]); return nil
    }
    if let existing = projectSources.first(where: { $0.projectID == projectID && $0.contentFingerprint == receipt.fingerprint }) {
      await ProjectSourceFiles.shared.remove([receipt.reference]); return existing.id
    }
    let suffix = (receipt.reference as NSString).pathExtension.lowercased()
    let kind: ProjectSource.Kind = suffix == "pdf" ? .pdf :
      ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif", "webp"].contains(suffix) ? .image : .document
    let source = ProjectSource(projectID: projectID, kind: kind, title: title,
      localFileReference: receipt.reference, contentFingerprint: receipt.fingerprint)
    guard storeProjectSource(source) else {
      await ProjectSourceFiles.shared.remove([receipt.reference]); return nil
    }
    await prepareProjectSource(source.id)
    return source.id
  }

  func prepareProjectSource(_ id: UUID) async {
    if let value = source(id: id), value.kind == .youtube {
      await prepareProjectYouTube(id, fetchMetadata: ProjectYouTubeMetadata.fetch, fetchThumbnail: { url in
        let data = try await ProjectYouTubeThumbnail.fetch(url)
        try Task.checkCancellation()
        let jpeg = await Task.detached(priority: .utility) {
          ImageDownscale.downsampled(data: data, maxPixelSize: 160)?.jpegData(compressionQuality: 0.8)
        }.value
        try Task.checkCancellation()
        guard let jpeg else { throw ProjectSourceFiles.Failure.invalidFile }
        return jpeg
      })
      return
    }
    await prepareProjectLocalSource(id, extract: ProjectSourceExtraction.extract)
  }

  @discardableResult
  func detachProjectSource(_ id: UUID) -> Bool {
    guard var source = source(id: id) else { return false }
    source.projectID = nil
    source.updatedAt = .now
    return storeProjectSource(source)
  }

  @discardableResult
  func deleteProjectSource(_ id: UUID) -> Bool {
    guard !isRestoring, let source = source(id: id) else { return false }
    let remaining = projectSources.filter { $0.id != id }
    guard persistNow(remaining, forKey: StorageKey.projectSources) else { return false }
    if let job = projectWebFetchJobs.removeValue(forKey: id) {
      job.task.cancel()
      projectSourceProcessingIDs.remove(id)
    }
    projectSources = remaining
    invalidateProjectEvidence([.source(id)])
    let retained = Set(remaining.flatMap(\.fileReferences))
    Task { await ProjectSourceFiles.shared.remove(source.fileReferences.filter { !retained.contains($0) }) }
    return true
  }
}
