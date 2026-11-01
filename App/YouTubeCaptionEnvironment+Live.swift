import Foundation

extension YouTubeCaptionService {
  static let shared = YouTubeCaptionService(environment: .live)
}

extension YouTubeCaptionEnvironment {
  static var live: Self {
    let authorization = GmailAuthorizationSession()
    return Self(clientID: { GmailService.clientID },
      refreshToken: { KeychainStore.string(forKey: "youtube.captions.refreshToken") },
      storeRefreshToken: { KeychainStore.set($0, forKey: "youtube.captions.refreshToken") },
      isDisconnected: { UserDefaults.standard.bool(forKey: "memora.youtube.disconnected") },
      setDisconnected: { UserDefaults.standard.set($0, forKey: "memora.youtube.disconnected") },
      authorize: { try await authorization.authorize(url: $0, scheme: $1) },
      cancelAuthorization: { authorization.cancel() },
      transport: { request in
        guard let url = request.url, let host = url.host,
              ["www.googleapis.com", "oauth2.googleapis.com"].contains(host) else { throw YouTubeCaptionService.Failure.unavailable }
        let addresses = try await MCPPublicAddressPolicy.validatedAddresses(for: host)
        var headers: [String: String] = ["accept": "application/json, text/vtt, text/plain, application/octet-stream"]
        if let value = request.value(forHTTPHeaderField: "Authorization") { headers["authorization"] = value }
        if let value = request.value(forHTTPHeaderField: "Content-Type") { headers["content-type"] = value }
        let pinned = try WebSourceRequest(url: url, addresses: addresses, body: request.httpBody, headers: headers)
        let result = try await PinnedHTTPSConnection.fetch(pinned, decoder: .init(maximumBodyBytes: 2 * 1024 * 1024,
          contentTypes: ["application/json", "text/vtt", "text/plain", "application/octet-stream"]))
        return (result.status, result.body)
      }, now: { .now })
  }
}
