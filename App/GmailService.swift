import CryptoKit
import Foundation
import Observation
import Security

/// Reads the person's Gmail, read-only, for Ask AI. Signing in uses Google's
/// OAuth with PKCE in the system web sheet; only the refresh token is kept,
/// in the keychain. Nothing is sent, changed or deleted in the mailbox.
///
/// The build needs a Google OAuth client ID for iOS under the Info.plist key
/// `MemoraGoogleClientID`. Without it the service says so instead of
/// pretending to connect.
@MainActor
@Observable
final class GmailService {
  static let shared = GmailService(environment: .live)

  private(set) var isConnected: Bool
  private(set) var connectedEmail: String?
  private(set) var isWorking = false
  @ObservationIgnored private(set) var connectionRevision = UUID()

  private static let scope = "https://www.googleapis.com/auth/gmail.readonly"
  private static let api = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

  @ObservationIgnored private var accessToken: String?
  @ObservationIgnored private var accessTokenExpiry = Date.distantPast
  @ObservationIgnored private let environment: GmailServiceEnvironment
  @ObservationIgnored private var isDisconnecting = false

  init(environment: GmailServiceEnvironment) {
    self.environment = environment
    let connected = !environment.isLocallyDisconnected() && environment.refreshToken()?.isEmpty == false
    isConnected = connected
    connectedEmail = connected ? environment.email() : nil
  }

  static var clientID: String? {
    let value = Bundle.main.object(forInfoDictionaryKey: "MemoraGoogleClientID") as? String
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  static var isConfigured: Bool { clientID != nil }

  /// Google's iOS clients redirect to the reversed client ID.
  private static func redirectScheme(for clientID: String) -> String {
    clientID.split(separator: ".").reversed().joined(separator: ".")
  }

  // MARK: - Connecting

  func connect() async throws {
    try Task.checkCancellation()
    guard !isWorking else { throw GmailError.cancelled }
    guard let clientID = environment.clientID() else { throw GmailError.notConfigured }
    connectionRevision = UUID()
    var revision = connectionRevision
    isWorking = true
    defer { if revision == connectionRevision { isWorking = false } }

    let verifier = Self.randomURLSafeString(byteCount: 48)
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    let state = Self.randomURLSafeString(byteCount: 16)
    let scheme = Self.redirectScheme(for: clientID)
    let redirectURI = "\(scheme):/oauth2redirect"

    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: "openid email \(Self.scope)"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "access_type", value: "offline"),
      URLQueryItem(name: "prompt", value: "consent")
    ]

    let callback = try await environment.authorize(components.url!, scheme)
    try Task.checkCancellation()
    guard revision == connectionRevision else { throw GmailError.cancelled }
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard callback.scheme == scheme, callback.path == "/oauth2redirect", callback.host == nil,
          items.filter({ $0.name == "state" }).count == 1,
          items.filter({ $0.name == "code" }).count == 1,
          items.first(where: { $0.name == "state" })?.value == state,
          let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
      throw GmailError.authorizationFailed
    }

    let token = try await requestToken([
      "client_id": clientID,
      "code": code,
      "code_verifier": verifier,
      "grant_type": "authorization_code",
      "redirect_uri": redirectURI
    ])
    guard revision == connectionRevision,
          let refresh = token.refreshToken, !refresh.isEmpty, environment.storeRefreshToken(refresh) else {
      throw GmailError.authorizationFailed
    }
    // Reads started while the previous account was still connected cannot be
    // accepted as results from the newly committed account.
    connectionRevision = UUID()
    revision = connectionRevision
    environment.setLocallyDisconnected(false)
    accessToken = token.accessToken
    accessTokenExpiry = environment.now().addingTimeInterval(token.expiresIn - 60)
    isConnected = true
    connectedEmail = nil
    environment.storeEmail(nil)

    let profile = try? await get(Self.api.appendingPathComponent("profile"))
    try Task.checkCancellation()
    guard revision == connectionRevision else { throw GmailError.cancelled }
    if let email = profile?["emailAddress"] as? String {
      connectedEmail = email
      environment.storeEmail(email)
    }
  }

  /// Forgets the connection and asks Google to revoke it.
  func disconnect() async {
    guard !isDisconnecting else { return }
    let refresh = environment.refreshToken()
    clearLocalConnection()
    environment.cancelAuthorization()
    isDisconnecting = true
    isWorking = true
    defer { isDisconnecting = false; isWorking = false }
    if let refresh, !refresh.isEmpty {
      var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
      request.httpMethod = "POST"
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      request.httpBody = Self.formBody(["token": refresh])
      _ = try? await environment.transport(request)
    }
  }

  private func clearLocalConnection() {
    connectionRevision = UUID()
    // A settings tombstone also protects the next launch if Keychain deletion
    // fails. It is cleared only after a new token has been stored successfully.
    environment.setLocallyDisconnected(true)
    _ = environment.storeRefreshToken(nil)
    environment.storeEmail(nil)
    accessToken = nil
    accessTokenExpiry = .distantPast
    connectedEmail = nil
    isConnected = false
    isWorking = false
  }

  // MARK: - Reading

  /// Mail matching a Gmail search, newest first, with sender, subject and
  /// the opening words.
  func search(_ query: String, limit: Int) async throws -> [GmailMessage] {
    let revision = connectionRevision
    var components = URLComponents(url: Self.api.appendingPathComponent("messages"), resolvingAgainstBaseURL: false)!
    var items = [URLQueryItem(name: "maxResults", value: "\(min(max(limit, 1), 60))")]
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    items.append(URLQueryItem(name: "q", value: trimmed.isEmpty ? "in:inbox" : trimmed))
    components.queryItems = items

    let list = try await get(components.url!)
    guard revision == connectionRevision else { throw ExternalToolFailure.authenticationExpired }
    guard list["messages"] == nil || list["messages"] is [[String: Any]] else { throw ExternalToolFailure.failed }
    let ids = try (list["messages"] as? [[String: Any]] ?? []).prefix(min(max(limit, 1), 60)).map { item in
      guard let id = item["id"] as? String else { throw ExternalToolFailure.failed }
      return id
    }
    var messages: [GmailMessage] = []
    for id in ids {
      var detail = URLComponents(url: try Self.messageURL(id), resolvingAgainstBaseURL: false)!
      detail.queryItems = [URLQueryItem(name: "format", value: "metadata")]
        + ["From", "To", "Subject", "Date"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
      let json = try await get(detail.url!)
      guard revision == connectionRevision else { throw ExternalToolFailure.authenticationExpired }
      guard json["id"] as? String == id else { throw ExternalToolFailure.failed }
      messages.append(Self.message(from: json, includeBody: false))
    }
    return messages
  }

  /// One mail with its text.
  func read(_ id: String) async throws -> GmailMessage {
    var components = URLComponents(url: try Self.messageURL(id), resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "format", value: "full")]
    let json = try await get(components.url!)
    guard json["id"] as? String == id else { throw ExternalToolFailure.failed }
    return Self.message(from: json, includeBody: true)
  }

  private static func messageURL(_ id: String) throws -> URL {
    guard !id.isEmpty, id.utf8.count <= 512,
          id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
      throw ExternalToolFailure.unavailable
    }
    return api.appendingPathComponent("messages").appendingPathComponent(id)
  }

  private func get(_ url: URL) async throws -> [String: Any] {
    let revision = connectionRevision
    try Task.checkCancellation()
    var request = URLRequest(url: url)
    request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
    guard revision == connectionRevision else { throw ExternalToolFailure.authenticationExpired }
    try Task.checkCancellation()
    let (data, response) = try await environment.transport(request)
    try Task.checkCancellation()
    guard revision == connectionRevision else { throw ExternalToolFailure.authenticationExpired }
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      if (response as? HTTPURLResponse)?.statusCode == 401 {
        // Keep a possibly valid refresh token, but never reuse the rejected
        // access token. A later explicit read may refresh; this call never retries.
        accessToken = nil
        accessTokenExpiry = .distantPast
      }
      throw ExternalToolFailure.http((response as? HTTPURLResponse)?.statusCode ?? 500)
    }
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ExternalToolFailure.failed }
    return json
  }

  private func validAccessToken() async throws -> String {
    let revision = connectionRevision
    try Task.checkCancellation()
    guard isConnected, !environment.isLocallyDisconnected(),
          let refresh = environment.refreshToken(), !refresh.isEmpty else { throw GmailError.notConnected }
    if let accessToken, accessTokenExpiry > environment.now() { return accessToken }
    guard let clientID = environment.clientID() else { throw GmailError.notConfigured }
    let token = try await requestToken([
      "client_id": clientID,
      "refresh_token": refresh,
      "grant_type": "refresh_token"
    ])
    guard revision == connectionRevision else { throw ExternalToolFailure.authenticationExpired }
    accessToken = token.accessToken
    accessTokenExpiry = environment.now().addingTimeInterval(token.expiresIn - 60)
    return token.accessToken
  }

  private func requestToken(_ fields: [String: String]) async throws -> (accessToken: String, refreshToken: String?, expiresIn: TimeInterval) {
    let revision = connectionRevision
    try Task.checkCancellation()
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.formBody(fields)
    let (data, response) = try await environment.transport(request)
    try Task.checkCancellation()
    guard revision == connectionRevision else { throw ExternalToolFailure.authenticationExpired }
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let access = json["access_token"] as? String, !access.isEmpty else {
      // Transient service failures must not revoke a still-valid connection.
      if let http = response as? HTTPURLResponse, (400..<500).contains(http.statusCode),
         fields["grant_type"] == "refresh_token", json["error"] as? String == "invalid_grant" {
        if fields["refresh_token"] == environment.refreshToken() {
          clearLocalConnection()
        }
        throw ExternalToolFailure.authenticationExpired
      }
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw ExternalToolFailure.http(http.statusCode)
      }
      throw GmailError.authorizationFailed
    }
    let expires = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
    guard expires.isFinite, expires > 0 else { throw GmailError.authorizationFailed }
    if let scopes = json["scope"] as? String,
       !scopes.split(separator: " ").contains(Substring(Self.scope)) {
      throw ExternalToolFailure.permissionDenied
    }
    return (access, json["refresh_token"] as? String, expires)
  }

  // MARK: - Parsing

  private static func message(from json: [String: Any], includeBody: Bool) -> GmailMessage {
    let payload = json["payload"] as? [String: Any] ?? [:]
    let headers = (payload["headers"] as? [[String: Any]] ?? []).reduce(into: [String: String]()) { result, header in
      if let name = header["name"] as? String, let value = header["value"] as? String {
        result[name.lowercased()] = value
      }
    }
    let date = (json["internalDate"] as? String).flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
    return GmailMessage(
      id: json["id"] as? String ?? "",
      from: headers["from"] ?? "",
      to: headers["to"] ?? "",
      subject: headers["subject"] ?? "（件名なし）",
      date: date,
      snippet: decodeEntities(json["snippet"] as? String ?? ""),
      body: includeBody ? bodyText(of: payload) : ""
    )
  }

  /// The plain text part, else the HTML part with its tags removed.
  private static func bodyText(of payload: [String: Any]) -> String {
    if let plain = part(in: payload, mimeType: "text/plain") { return plain }
    if let html = part(in: payload, mimeType: "text/html") {
      return decodeEntities(
        html.replacingOccurrences(of: "<br[^>]*>|</p>|</div>", with: "\n", options: .regularExpression)
          .replacingOccurrences(of: "<style[\\s\\S]*?</style>|<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
          .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      )
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }
    return ""
  }

  private static func part(in payload: [String: Any], mimeType: String) -> String? {
    if payload["mimeType"] as? String == mimeType,
       let data = (payload["body"] as? [String: Any])?["data"] as? String,
       let decoded = Data(base64URLEncoded: data),
       let text = String(data: decoded, encoding: .utf8) {
      return text
    }
    for child in payload["parts"] as? [[String: Any]] ?? [] {
      if let found = part(in: child, mimeType: mimeType) { return found }
    }
    return nil
  }

  private static func decodeEntities(_ text: String) -> String {
    text.replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&nbsp;", with: " ")
  }

  private static func formBody(_ fields: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return fields
      .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
      .joined(separator: "&")
      .data(using: .utf8) ?? Data()
  }

  private static func randomURLSafeString(byteCount: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    return Data(bytes).base64URLEncoded
  }
}

private extension Data {
  var base64URLEncoded: String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  init?(base64URLEncoded string: String) {
    var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    self.init(base64Encoded: base64)
  }
}
