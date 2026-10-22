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

}
