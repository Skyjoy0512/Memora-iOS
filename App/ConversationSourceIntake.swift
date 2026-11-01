import Foundation

enum ConversationSourceIntake {
  static func prepare(_ url: URL, fetcher: WebSourceFetcher = .init()) async throws -> AIAttachment {
    let link = try ProjectSourceURL.normalized(url.absoluteString)
    if let videoID = link.youtubeID {
      let service = await YouTubeCaptionService.shared
      let captions = try await service.captions(videoID: videoID)
      let metadata = try? await ProjectYouTubeMetadata.fetch(link.url)
      let data = try JSONEncoder().encode(ConversationLinkSnapshot(originalURL: link.url,
        title: metadata?.title ?? "YouTube", fetchedAt: .now, blocks: SubtitleText.blocks(captions),
        notice: "YouTube公式APIで権限を確認して取得した字幕です。映像は解析していません。"))
      return try await save(data, suffix: "memorasource", title: metadata?.title ?? "YouTube", originalURL: link.url)
    }
    let result = try await fetcher.fetch(link.url)
    try Task.checkCancellation()
    let data: Data
    let suffix: String
    if let fileData = result.fileData { data = fileData; suffix = "pdf" }
    else {
      data = try JSONEncoder().encode(ConversationLinkSnapshot(originalURL: link.url,
        title: result.content.title ?? link.url.host ?? "Web資料", fetchedAt: result.fetchedAt,
        blocks: result.content.blocks, notice: result.content.notice))
      suffix = "memorasource"
    }
    return try await save(data, suffix: suffix, title: result.content.title ?? link.url.host ?? "Web資料", originalURL: link.url)
  }

  private static func save(_ data: Data, suffix: String, title: String, originalURL: URL) async throws -> AIAttachment {
    guard data.count <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    let reference = try await AIAttachmentFiles.shared.write(data, extension: suffix)
    let file = try AIAttachmentFiles.url(reference)
    return AIAttachment(id: UUID(), name: title, url: file, originalURL: originalURL)
  }

  enum Failure: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { message } else { nil } }
  }
}
