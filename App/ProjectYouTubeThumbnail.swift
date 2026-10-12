import Foundation

enum ProjectYouTubeThumbnail {
  static func request(for originalURL: URL) throws -> URLRequest {
    let link = try ProjectSourceURL.normalized(originalURL.absoluteString)
    guard link.kind == .youtube, let id = link.youtubeID,
          let url = URL(string: "https://i.ytimg.com/vi/\(id)/default.jpg") else {
      throw ProjectYouTubeMetadata.Failure.unavailable
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
    return request
  }

  static func fetch(_ originalURL: URL) async throws -> Data {
    try await ProjectMetadataTransport.data(for: request(for: originalURL), host: "i.ytimg.com",
      mimeTypes: ["image/jpeg", "image/png"], maximumBytes: 128 * 1024)
  }
}
