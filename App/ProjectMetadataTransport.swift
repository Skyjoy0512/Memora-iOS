import Foundation

enum ProjectMetadataTransport {
  static func data(for request: URLRequest, host: String, mimeTypes: Set<String>, maximumBytes: Int,
                   sessionConfiguration: URLSessionConfiguration = .ephemeral) async throws -> Data {
    guard ["www.youtube.com", "i.ytimg.com", "api.search.brave.com"].contains(host),
          request.url?.host == host, request.url?.scheme == "https", maximumBytes > 0 else {
      throw ProjectYouTubeMetadata.Failure.unavailable
    }
    let configuration = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = 20
    let session = URLSession(configuration: configuration, delegate: ProjectMetadataRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          http.url?.host == host, let mime = http.mimeType, mimeTypes.contains(mime),
          http.expectedContentLength <= maximumBytes else { throw ProjectYouTubeMetadata.Failure.unavailable }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximumBytes else { throw ProjectYouTubeMetadata.Failure.unavailable }
      data.append(byte)
    }
    return data
  }
}
