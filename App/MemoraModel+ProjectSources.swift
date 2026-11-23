import Foundation

extension MemoraModel {
  @discardableResult
  func addProjectLink(_ input: String, projectID: UUID?, removing: [String] = []) async throws -> UUID? {
    guard let context = LocalImportContext(projectID: projectID, in: self) else { return nil }
    let link = try ProjectSourceURL.normalized(input)
    let title = link.youtubeID.map { "YouTube · \($0)" } ?? link.url.host ?? "Webリンク"
    let intent = CaptureIntent.url(link.url)
    // The coordinator settles the drafts in the same transaction as the
    // record, so a saved link never leaves a draft that restores as a
    // duplicate.
    let outcome = await capture(intent, context: context, title: title, removing: removing)
    // Reusing a source must not dispatch another paid preparation job.
    // Re-adding a source that previously failed is an explicit retry.
    switch outcome {
    case .imported(let id):
      return id
    case .duplicate(let id):
      if let existing = source(id: id), existing.processingStatus == .failed {
        scheduleProjectSourcePreparation(id)
      }
      return id
    case .refused:
      return nil
    }
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
        await prepareProjectLocalSource(id) { try await SourceExtractionCache.shared.extract($0, vocabulary: vocabulary) }
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
    await prepareProjectLocalSource(id) { try await SourceExtractionCache.shared.extract($0, vocabulary: vocabulary) }
    await summarizeProjectSource(id)
  }

}
