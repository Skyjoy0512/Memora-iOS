import Foundation

/// One ChatGPT sign-in attempt: the authorization request, the code
/// exchange, the refresh of stored credentials and the revocation.
struct ChatGPTOAuthTransaction: Sendable {
  /// The issuer OpenAI signs its tokens with.
  static let issuer = "https://auth.openai.com"
  /// Where the person authorizes Memora.
  static let authorizationEndpoint = "https://auth.openai.com/api/accounts/authorize"
  /// Where codes and refresh tokens are exchanged.
  static let tokenEndpoint = "https://auth.openai.com/api/accounts/oauth/token"
  /// Where a refresh token is revoked.
  static let revocationEndpoint = "https://auth.openai.com/api/accounts/oauth/revoke"
  /// The API resource the tokens are for.
  static let resource = "https://api.openai.com/v1"
  /// The client ID that asks OpenAI to register this app.
  static let dynamicClientID = "dynamic_agent_client"
  /// The path the loopback callback answers on.
  static let redirectPath = "/auth/callback"

  /// The authorization request Memora sends to OpenAI.
  struct AuthorizationRequest: Equatable, Sendable {
    /// The URL to open in a browser.
    var url: URL
    /// The value that ties the callback to this request.
    var state: String
    /// The value the returned identity token must carry.
    var nonce: String
    /// The PKCE verifier for this request.
    var verifier: String
    /// The redirect URI that was sent with the request.
    var redirectURI: URL
  }

  /// Builds the authorization request.
  ///
  /// `clientID` is the issued client ID of an earlier registration, or `nil`
  /// the first time. `hostID` is this installation's agent host ID and is
  /// always sent. `loginHint` is the email of the account to preselect, when
  /// one is known. `redirectURI` is the loopback address the sign-in page must
  /// answer on.
  ///
  /// The request carries PKCE (S256), a fresh `state` and a fresh `nonce`, the
  /// scope string `ChatGPTScope.all` and the resource. `agent_name_hint` is
  /// sent only when there is no issued client ID yet. `login_hint` is sent
  /// only when one is given.
  static func makeAuthorizationRequest(clientID: String?, hostID: String,
    loginHint: String?, redirectURI: URL) throws -> AuthorizationRequest {
    if let clientID {
      guard isIssuedClientID(clientID) else {
        throw ChatGPTSignInError.registrationIncomplete
      }
    }
    guard !hostID.isEmpty, hostID.utf8.count <= 512,
          redirectURI.scheme == "http", redirectURI.host == "127.0.0.1" else {
      throw ChatGPTSignInError.callbackFailed
    }

    let state = randomValue()
    let nonce = randomValue()
    let verifier = randomValue()
    let challenge = ChatGPTOAuthEncoding.challenge(for: verifier)

    var items = [
      URLQueryItem(name: "client_id", value: clientID ?? dynamicClientID),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
      URLQueryItem(name: "scope", value: ChatGPTScope.all),
      URLQueryItem(name: "resource", value: resource),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "nonce", value: nonce),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "ext_agent_host_id", value: hostID)
    ]
    if clientID == nil {
      items.append(URLQueryItem(name: "agent_name_hint", value: "Memora"))
    }
    if let loginHint, !loginHint.isEmpty, loginHint.utf8.count <= 512 {
      items.append(URLQueryItem(name: "login_hint", value: loginHint))
    }

    guard var components = URLComponents(string: authorizationEndpoint) else {
      throw ChatGPTSignInError.callbackFailed
    }
    components.queryItems = items
    guard let url = components.url else {
      throw ChatGPTSignInError.callbackFailed
    }
    return AuthorizationRequest(url: url, state: state, nonce: nonce, verifier: verifier,
      redirectURI: redirectURI)
  }

  /// Exchanges an authorization code for credentials.
  ///
  /// The request is form encoded and carries `grant_type`, `client_id`,
  /// `code`, `code_verifier`, `redirect_uri` and `resource`. The response is
  /// parsed with `ChatGPTTokenResponse`.
  static func exchange(code: String, clientID: String, verifier: String,
    redirectURI: URL) async throws -> ChatGPTTokenResponse {
    guard isIssuedClientID(clientID) else { throw ChatGPTSignInError.registrationIncomplete }
    let body = [
      "grant_type": "authorization_code",
      "client_id": clientID,
      "code": code,
      "code_verifier": verifier,
      "redirect_uri": redirectURI.absoluteString,
      "resource": resource
    ]
    return try await tokenRequest(body)
  }

  /// Refreshes credentials with a refresh token.
  ///
  /// The request carries `grant_type`, `client_id`, `refresh_token` and
  /// `resource`. The response must carry a refresh token again; without one
  /// the credentials cannot be renewed and `ChatGPTSignInError.invalidResponse`
  /// is thrown.
  static func refresh(refreshToken: String, clientID: String) async throws -> ChatGPTTokenResponse {
    guard isIssuedClientID(clientID) else { throw ChatGPTSignInError.registrationIncomplete }
    let body = [
      "grant_type": "refresh_token",
      "client_id": clientID,
      "refresh_token": refreshToken,
      "resource": resource
    ]
    let response = try await tokenRequest(body)
    guard let renewed = response.refreshToken, !renewed.isEmpty else {
      throw ChatGPTSignInError.invalidResponse
    }
    return response
  }

  /// Revokes a refresh token, so the session cannot be renewed.
  ///
  /// The request carries `token`, `token_type_hint` and `client_id`. A failure
  /// to reach the service throws `ChatGPTSignInError.serviceUnavailable`; the
  /// caller decides what to do with the local credentials.
  static func revoke(refreshToken: String, clientID: String) async throws {
    guard isIssuedClientID(clientID) else { throw ChatGPTSignInError.registrationIncomplete }
    let body = [
      "token": refreshToken,
      "token_type_hint": "refresh_token",
      "client_id": clientID
    ]
    _ = try await post(url: revocationEndpoint, body: body)
  }

  /// Whether a client ID looks like one OpenAI issued for a registration.
  static func isIssuedClientID(_ clientID: String) -> Bool {
    guard !clientID.isEmpty, clientID.utf8.count <= 200, clientID != dynamicClientID else {
      return false
    }
    return clientID.utf8.allSatisfy { byte in
      (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
        || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x5F
    }
  }

  private static func tokenRequest(_ body: [String: String]) async throws -> ChatGPTTokenResponse {
    let data = try await post(url: tokenEndpoint, body: body)
    do {
      return try ChatGPTTokenResponse.decode(data)
    } catch {
      throw ChatGPTSignInError.invalidResponse
    }
  }

  private static func post(url: String, body: [String: String]) async throws -> Data {
    guard let endpoint = URL(string: url) else { throw ChatGPTSignInError.invalidResponse }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = ChatGPTOAuthEncoding.form(body)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.timeoutInterval = 30

    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw ChatGPTSignInError.serviceUnavailable
    }
    guard let http = response as? HTTPURLResponse else {
      throw ChatGPTSignInError.invalidResponse
    }
    if http.statusCode == 500 || http.statusCode == 502 || http.statusCode == 503
      || http.statusCode == 504 || http.statusCode == 429 {
      throw ChatGPTSignInError.serviceUnavailable
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ChatGPTSignInError.invalidResponse
    }
    return data
  }

  private static func randomValue() -> String {
    ChatGPTOAuthEncoding.randomValue()
  }
}
