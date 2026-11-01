import Foundation

extension MemoraModel {
  @discardableResult
  func addProjectLink(_ input: String, projectID: UUID?) throws -> UUID? {
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
          projectID.map({ space(id: $0) != nil }) ?? true else { return nil }
    let link = try ProjectSourceURL.normalized(input)
    if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
      return existing.id
    }
    let source = ProjectSource(projectID: projectID, kind: link.kind,
      title: link.youtubeID.map { "YouTube · \($0)" } ?? link.url.host ?? "Webリンク", originalURL: link.url)
    guard storeProjectSource(source) else { return nil }
    scheduleProjectSourcePreparation(source.id)
    return source.id
  }

  func performProjectSourcePreparation(_ id: UUID) async {
    if let value = source(id: id), value.kind == .web {
      if !value.canProvideText { await acquireRemoteSource(id) }
      await summarizeProjectSource(id)
      return
    }
    if let value = source(id: id), value.kind == .youtube {
      await prepareLegacySourceTranscript(id)
      if source(id: id)?.canProvideText == true { await summarizeProjectSource(id); return }
      if source(id: id)?.localFileReference != nil {
        let vocabulary = transcriptionVocabulary
        await prepareProjectLocalSource(id) { try await SourceIntake.extract($0, vocabulary: vocabulary) }
        await summarizeProjectSource(id)
        return
      }
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
      await prepareAuthorizedYouTubeCaptions(id)
      return
    }
    let vocabulary = transcriptionVocabulary
    await prepareProjectLocalSource(id) { try await SourceIntake.extract($0, vocabulary: vocabulary) }
    await summarizeProjectSource(id)
  }

}
