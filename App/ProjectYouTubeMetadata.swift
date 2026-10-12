import Foundation

enum ProjectYouTubeMetadata {
  struct Value: Equatable, Sendable {
    var title: String
    var author: String
  }

  enum Failure: Error { case unavailable }

  static func request(for originalURL: URL) throws -> URLRequest {
    let link = try ProjectSourceURL.normalized(originalURL.absoluteString)
    guard link.kind == .youtube, let id = link.youtubeID else { throw Failure.unavailable }
    // Only a validated video ID enters this fixed first-party endpoint.
    var components = URLComponents(string: "https://www.youtube.com/oembed")!
    components.queryItems = [URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
                             URLQueryItem(name: "format", value: "json")]
    guard let url = components.url else { throw Failure.unavailable }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  static func decode(_ data: Data) throws -> Value {
    guard data.count <= 65_536,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["type"] as? String == "video", object["provider_name"] as? String == "YouTube",
          let title = object["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw Failure.unavailable
    }
    return Value(title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
      author: String((object["author_name"] as? String ?? "").prefix(200)))
  }

  static func fetch(_ originalURL: URL) async throws -> Value {
    let data = try await ProjectMetadataTransport.data(for: request(for: originalURL), host: "www.youtube.com",
      mimeTypes: ["application/json"], maximumBytes: 65_536)
    return try decode(data)
  }
}
