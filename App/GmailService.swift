import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

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
  static let shared = GmailService()

  private(set) var isConnected = KeychainStore.string(forKey: GmailService.refreshTokenKey) != nil
  private(set) var connectedEmail = UserDefaults.standard.string(forKey: GmailService.emailKey)
  private(set) var isWorking = false

  private static let refreshTokenKey = "gmail.refreshToken"
  private static let emailKey = "memora.gmail.email"
  private static let scope = "https://www.googleapis.com/auth/gmail.readonly"
  private static let api = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

  @ObservationIgnored private var accessToken: String?
  @ObservationIgnored private var accessTokenExpiry = Date.distantPast
  @ObservationIgnored private var authSession: ASWebAuthenticationSession?
  @ObservationIgnored private let presentation = GmailPresentationAnchor()

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
    guard let clientID = Self.clientID else { throw GmailError.notConfigured }
    isWorking = true
    defer { isWorking = false }

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

    let callback = try await authorize(url: components.url!, scheme: scheme)
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard items.first(where: { $0.name == "state" })?.value == state,
          let code = items.first(where: { $0.name == "code" })?.value else {
      throw GmailError.authorizationFailed
    }

    let token = try await requestToken([
      "client_id": clientID,
      "code": code,
      "code_verifier": verifier,
      "grant_type": "authorization_code",
      "redirect_uri": redirectURI
    ])
    guard let refresh = token.refreshToken, KeychainStore.set(refresh, forKey: Self.refreshTokenKey) else {
      throw GmailError.authorizationFailed
    }
    accessToken = token.accessToken
    accessTokenExpiry = Date.now.addingTimeInterval(token.expiresIn - 60)
    isConnected = true

    if let profile = try? await get(Self.api.appendingPathComponent("profile")),
       let email = profile["emailAddress"] as? String {
      connectedEmail = email
      UserDefaults.standard.set(email, forKey: Self.emailKey)
    }
  }

  /// Forgets the connection and asks Google to revoke it.
  func disconnect() async {
    if let refresh = KeychainStore.string(forKey: Self.refreshTokenKey) {
      var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
      request.httpMethod = "POST"
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      request.httpBody = Self.formBody(["token": refresh])
      _ = try? await URLSession.shared.data(for: request)
    }
    KeychainStore.set(nil, forKey: Self.refreshTokenKey)
    UserDefaults.standard.removeObject(forKey: Self.emailKey)
    accessToken = nil
    accessTokenExpiry = .distantPast
    connectedEmail = nil
    isConnected = false
  }

  private func authorize(url: URL, scheme: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
        if let callback {
          continuation.resume(returning: callback)
        } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          continuation.resume(throwing: GmailError.cancelled)
        } else {
          continuation.resume(throwing: GmailError.authorizationFailed)
        }
      }
      session.presentationContextProvider = presentation
      authSession = session
      if !session.start() {
        continuation.resume(throwing: GmailError.authorizationFailed)
      }
    }
  }

  // MARK: - Reading

  /// Mail matching a Gmail search, newest first, with sender, subject and
  /// the opening words.
  func search(_ query: String, limit: Int) async throws -> [GmailMessage] {
    var components = URLComponents(url: Self.api.appendingPathComponent("messages"), resolvingAgainstBaseURL: false)!
    var items = [URLQueryItem(name: "maxResults", value: "\(min(max(limit, 1), 60))")]
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    items.append(URLQueryItem(name: "q", value: trimmed.isEmpty ? "in:inbox" : trimmed))
    components.queryItems = items

    let list = try await get(components.url!)
    let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    var messages: [GmailMessage] = []
    for id in ids {
      var detail = URLComponents(url: Self.api.appendingPathComponent("messages/\(id)"), resolvingAgainstBaseURL: false)!
      detail.queryItems = [URLQueryItem(name: "format", value: "metadata")]
        + ["From", "To", "Subject", "Date"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
      let json = try await get(detail.url!)
      messages.append(Self.message(from: json, includeBody: false))
    }
    return messages
  }

  /// One mail with its text.
  func read(_ id: String) async throws -> GmailMessage {
    var components = URLComponents(url: Self.api.appendingPathComponent("messages/\(id)"), resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "format", value: "full")]
    return Self.message(from: try await get(components.url!), includeBody: true)
  }

  private func get(_ url: URL) async throws -> [String: Any] {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw ExternalToolFailure.http((response as? HTTPURLResponse)?.statusCode ?? 500)
    }
    return json
  }

  private func validAccessToken() async throws -> String {
    if let accessToken, accessTokenExpiry > .now { return accessToken }
    guard let clientID = Self.clientID else { throw GmailError.notConfigured }
    guard let refresh = KeychainStore.string(forKey: Self.refreshTokenKey) else { throw GmailError.notConnected }
    let token = try await requestToken([
      "client_id": clientID,
      "refresh_token": refresh,
      "grant_type": "refresh_token"
    ])
    accessToken = token.accessToken
    accessTokenExpiry = Date.now.addingTimeInterval(token.expiresIn - 60)
    return token.accessToken
  }

  private func requestToken(_ fields: [String: String]) async throws -> (accessToken: String, refreshToken: String?, expiresIn: TimeInterval) {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.formBody(fields)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let access = json["access_token"] as? String else {
      // A revoked or expired refresh token cannot recover; the person
      // connects again.
      if fields["grant_type"] == "refresh_token" {
        await disconnect()
        throw GmailError.notConnected
      }
      throw GmailError.authorizationFailed
    }
    let expires = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
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

/// Shows Google's sign-in over the app's active window.
private final class GmailPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
      return scene?.keyWindow ?? ASPresentationAnchor()
    }
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
