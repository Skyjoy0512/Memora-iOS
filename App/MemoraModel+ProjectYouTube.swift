import Foundation

extension MemoraModel {
  func prepareProjectYouTube(_ id: UUID,
    fetchMetadata: (URL) async throws -> ProjectYouTubeMetadata.Value,
    fetchThumbnail: (URL) async throws -> Data
  ) async {
    guard var context = ProjectSourcePreparationContext(id, in: self),
          context.source.kind == .youtube, let url = context.source.originalURL,
          context.source.metadata?["youtubeTitle"] == nil || context.source.thumbnailReference == nil,
          !projectSourceProcessingIDs.contains(id) else { return }
    projectSourceProcessingIDs.insert(id)
    defer {
      projectSourceProcessingIDs.remove(id)
      recoverInterruptedProjectSources()
    }
    if context.source.metadata?["youtubeTitle"] == nil {
      context.source.processingStatus = .processing
      guard storeProjectSource(context.source) else { return }
      do {
        let metadata = try await fetchMetadata(url)
        try Task.checkCancellation()
        guard context.isCurrent(in: self) else { return }
        var current = context.source
        current.title = metadata.title
        var values = current.metadata ?? [:]
        values["youtubeTitle"] = metadata.title
        values["youtubeAuthor"] = metadata.author
        current.metadata = values
        current.processingStatus = .unavailable
        current.errorInformation = "動画情報を取得しました。字幕や動画内容は取得していないため、AIの根拠には使用しません。"
        guard storeProjectSource(current) else { return }
        context.source = current
      } catch {
        guard context.isCurrent(in: self, allowsCancellation: true) else { return }
        var current = context.source
        current.processingStatus = .unavailable
        current.errorInformation = error is CancellationError
          ? "動画情報の取得を停止しました。リンクは保存されています。"
          : "動画情報を取得できませんでした。リンクは保存されています。"
        _ = storeProjectSource(current)
        return
      }
    }
    guard context.isCurrent(in: self), context.source.thumbnailReference == nil else { return }
    var created: String?
    do {
      let jpeg = try await fetchThumbnail(url)
      try Task.checkCancellation()
      guard context.isCurrent(in: self) else { return }
      let name = try await ProjectSourceFiles.shared.write(jpeg, extension: "jpg")
      created = name
      guard context.isCurrent(in: self) else {
        await ProjectSourceFiles.shared.remove([name]); return
      }
      var current = context.source
      current.thumbnailReference = name
      current.metadata?.removeValue(forKey: "thumbnailError")
      if !storeProjectSource(current) { await ProjectSourceFiles.shared.remove([name]) }
    } catch {
      if let created { await ProjectSourceFiles.shared.remove([created]) }
      guard context.isCurrent(in: self) else { return }
      var current = context.source
      var values = current.metadata ?? [:]
      values["thumbnailError"] = (error as? ProjectSourceFiles.Failure)?.errorDescription ??
        "サムネイルを取得できませんでした。動画リンクと情報は保存されています。"
      current.metadata = values
      _ = storeProjectSource(current)
    }
  }
}
