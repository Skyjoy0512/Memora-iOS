import Foundation

extension MemoraModel {
  func prepareAuthorizedYouTubeCaptions(_ id: UUID, retry: Bool = false) async {
    let service = YouTubeCaptionService.shared
    guard service.isConnected, var snapshot = ProjectSourcePreparationContext(id, in: self),
          snapshot.source.kind == .youtube, let url = snapshot.source.originalURL,
          let videoID = try? ProjectSourceURL.normalized(url.absoluteString).youtubeID,
          !snapshot.source.canProvideText || retry, !projectSourceProcessingIDs.contains(id) else { return }
    projectSourceProcessingIDs.insert(id)
    defer { projectSourceProcessingIDs.remove(id); recoverInterruptedProjectSources() }
    snapshot.source.processingStatus = .processing
    guard storeProjectSource(snapshot.source) else { return }
    let expected = snapshot
    do {
      let text = try await service.captions(videoID: videoID) { expected.isCurrent(in: self) }
      guard snapshot.isCurrent(in: self) else { return }
      projectSourceProcessingIDs.remove(id)
      _ = try await importSourceTranscript(text, source: snapshot.source,
        context: LocalImportContext(projectID: snapshot.source.projectID, in: self),
        notice: "YouTube公式APIから、接続アカウントの権限で取得した字幕です。映像は解析していません。")
    } catch {
      guard snapshot.isCurrent(in: self, allowsCancellation: true) else { return }
      snapshot.source.processingStatus = snapshot.source.extractedTextReference == nil ? .unavailable : .ready
      snapshot.source.errorInformation = error.localizedDescription
      _ = storeProjectSource(snapshot.source)
    }
  }
}
