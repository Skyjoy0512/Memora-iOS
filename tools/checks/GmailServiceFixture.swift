import CryptoKit
import Foundation

/// All account, browser, storage, clock and HTTP inputs are isolated fixtures.
/// Unexpected endpoints fail closed; neither shared service nor live adapters run.
@MainActor
final class GmailServiceFixture {
  var refresh: String? = "fixture-refresh"
  var email: String? = "fixture@example.invalid"
  var disconnected = false
  var failsStorage = false
  var clientID: String? = "fixture.apps.googleusercontent.com"
  var now = Date(timeIntervalSince1970: 1_700_000_000)
  var requests: [URLRequest] = []
  var authorizations: [URL] = []
  var cancellations = 0
  var transportOverride: ((URLRequest) async throws -> (Data, URLResponse))?
  var authorizeOverride: ((URL, String) async throws -> URL)?

  var environment: GmailServiceEnvironment {
    GmailServiceEnvironment(
      clientID: { self.clientID }, refreshToken: { self.refresh },
      storeRefreshToken: { value in
        if self.failsStorage { return false }
        self.refresh = value
        return true
      }, email: { self.email }, storeEmail: { self.email = $0 },
      isLocallyDisconnected: { self.disconnected }, setLocallyDisconnected: { self.disconnected = $0 },
      authorize: { url, scheme in
        self.authorizations.append(url)
        return try await self.authorizeOverride?(url, scheme) ?? self.callback(url, scheme)
      }, cancelAuthorization: { self.cancellations += 1 },
      transport: { request in
        self.requests.append(request)
        if let transport = self.transportOverride { return try await transport(request) }
        return self.response(request)
      }, now: { self.now }
    )
  }

  func callback(_ url: URL, _ scheme: String) -> URL {
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(query.first { $0.name == "scope" }?.value == "openid email https://www.googleapis.com/auth/gmail.readonly")
    precondition(query.first { $0.name == "code_challenge_method" }?.value == "S256")
    let state = query.first { $0.name == "state" }!.value!
    return URL(string: "\(scheme):/oauth2redirect?state=\(state)&code=fixture-code")!
  }

  func response(_ request: URLRequest, status: Int = 200, json: [String: Any]? = nil) -> (Data, URLResponse) {
    let url = request.url!
    let body: [String: Any]
    switch (url.host, url.path) {
    case ("oauth2.googleapis.com", "/token"):
      precondition(request.httpMethod == "POST")
      body = ["access_token": "fixture-access", "refresh_token": "new-fixture-refresh", "expires_in": 3600,
        "scope": "openid email https://www.googleapis.com/auth/gmail.readonly"]
    case ("oauth2.googleapis.com", "/revoke"):
      precondition(request.httpMethod == "POST")
      body = [:]
    case ("gmail.googleapis.com", "/gmail/v1/users/me/profile"):
      body = ["emailAddress": "connected@example.invalid"]
    case ("gmail.googleapis.com", "/gmail/v1/users/me/messages"):
      body = ["messages": [["id": "message1"], ["id": "message2"]]]
    case ("gmail.googleapis.com", let path) where path.hasPrefix("/gmail/v1/users/me/messages/message"):
      let id = url.lastPathComponent
      body = ["id": id, "internalDate": "1700000000000", "snippet": "Fixture &amp; text",
        "payload": ["mimeType": "text/plain", "headers": [
          ["name": "From", "value": "fixture@example.invalid"], ["name": "Subject", "value": "Fixture subject"]
        ], "body": ["data": Data("本文のfixture".utf8).base64EncodedString()]]]
    default: preconditionFailure("Unexpected fixture endpoint")
    }
    return (try! JSONSerialization.data(withJSONObject: json ?? body),
      HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
  }
}

extension GmailServiceEnvironment {
  static var live: Self { preconditionFailure("Host checks must never open live Gmail adapters") }
}
