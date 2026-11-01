import CryptoKit
import Foundation
import Observation
import Security

/// The official owner-authorized API only. No timedtext scraping or video
/// download, and Gmail's credentials are never reused for another OAuth scope.
@MainActor @Observable
final class YouTubeCaptionService {
  private(set) var isConnected: Bool
  private(set) var isWorking = false
  private(set) var revision = UUID()
  @ObservationIgnored private var environment: YouTubeCaptionEnvironment
  @ObservationIgnored private var accessToken: String?
  @ObservationIgnored private var expiresAt = Date.distantPast
  static let scope = "https://www.googleapis.com/auth/youtube.force-ssl"

  init(environment: YouTubeCaptionEnvironment) {
    self.environment = environment
    isConnected = !environment.isDisconnected() && environment.refreshToken()?.isEmpty == false
  }

  var isConfigured: Bool { environment.clientID()?.isEmpty == false }

  func connect() async throws {
    guard !isWorking, let clientID = environment.clientID(), !clientID.isEmpty else { throw Failure.notConfigured }
    revision = UUID(); let attempt = revision
    isWorking = true
    defer { if revision == attempt { isWorking = false } }
    let verifier = try Self.random(48), state = try Self.random(24)
    let challenge = Self.urlSafe(Data(SHA256.hash(data: Data(verifier.utf8))))
    let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
    let redirect = "\(scheme):/oauth2redirect"
    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    components.queryItems = ["client_id": clientID, "redirect_uri": redirect, "response_type": "code",
      "scope": Self.scope, "code_challenge": challenge, "code_challenge_method": "S256", "state": state,
      "access_type": "offline", "prompt": "consent"].map { URLQueryItem(name: $0.key, value: $0.value) }
    let callback = try await environment.authorize(components.url!, scheme)
    try Task.checkCancellation()
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard revision == attempt, callback.scheme == scheme, callback.host == nil, callback.path == "/oauth2redirect",
          items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == state,
          items.filter({ $0.name == "code" }).count == 1, let code = items.first(where: { $0.name == "code" })?.value,
          !code.isEmpty else { throw Failure.notAuthorized }
    let token = try await token(["client_id": clientID, "redirect_uri": redirect, "code": code,
      "code_verifier": verifier, "grant_type": "authorization_code"])
    guard revision == attempt, let refresh = token.refresh, !refresh.isEmpty,
          environment.storeRefreshToken(refresh) else { throw Failure.notAuthorized }
    environment.setDisconnected(false)
    accessToken = token.access; expiresAt = environment.now().addingTimeInterval(token.expires - 60)
    isConnected = true
  }

  func disconnect() {
    revision = UUID()
    environment.setDisconnected(true)
    _ = environment.storeRefreshToken(nil)
    environment.cancelAuthorization()
    accessToken = nil; expiresAt = .distantPast
    isConnected = false; isWorking = false
  }

  func captions(videoID: String, isAuthorized: @escaping @MainActor () -> Bool = { true }) async throws -> String {
    guard videoID.utf8.count == 11, Self.safeID(videoID), isConnected else { throw Failure.notConnected }
    let attempt = revision
    var list = URLComponents(string: "https://www.googleapis.com/youtube/v3/captions")!
    list.queryItems = [URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "videoId", value: videoID)]
    let data = try await read(list.url!, attempt: attempt, isAuthorized: isAuthorized)
    let tracks = try JSONDecoder().decode(Tracks.self, from: data).items.filter { $0.snippet.isDraft != true && $0.snippet.status != "failed" }
    guard let track = tracks.first(where: { $0.snippet.language == "ja" }) ?? tracks.first,
          Self.safeID(track.id) else { throw Failure.noCaptions }
    var download = URLComponents(url: URL(string: "https://www.googleapis.com/youtube/v3/captions")!.appendingPathComponent(track.id), resolvingAgainstBaseURL: false)!
    download.queryItems = [URLQueryItem(name: "tfmt", value: "vtt")]
    let bytes = try await read(download.url!, attempt: attempt, isAuthorized: isAuthorized)
    guard let text = String(data: bytes, encoding: .utf8), text.contains("-->"), !SubtitleText.blocks(text).isEmpty else { throw Failure.noCaptions }
    return text
  }

  private func read(_ url: URL, attempt: UUID, isAuthorized: @MainActor () -> Bool) async throws -> Data {
    guard revision == attempt, isConnected, isAuthorized() else { throw Failure.notAuthorized }
    if accessToken == nil || expiresAt <= environment.now() {
      guard let clientID = environment.clientID(), let refresh = environment.refreshToken() else { throw Failure.notConnected }
      let value = try await token(["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
      guard revision == attempt, isConnected, isAuthorized() else { throw Failure.notAuthorized }
      accessToken = value.access; expiresAt = environment.now().addingTimeInterval(value.expires - 60)
    }
    try Task.checkCancellation()
    guard revision == attempt, isConnected, isAuthorized(), let accessToken else { throw Failure.notAuthorized }
    var request = URLRequest(url: url)
    request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
    let response = try await environment.transport(request)
    try Task.checkCancellation()
    guard revision == attempt, isConnected, isAuthorized() else { throw Failure.notAuthorized }
    if response.status == 401 { self.accessToken = nil; throw Failure.notAuthorized }
    if response.status == 403 { throw Failure.notAuthorized }
    guard response.status == 200, response.body.count <= 2 * 1024 * 1024 else { throw Failure.unavailable }
    return response.body
  }

  private func token(_ fields: [String: String]) async throws -> (access: String, refresh: String?, expires: TimeInterval) {
    let attempt = revision
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
    let response = try await environment.transport(request)
    try Task.checkCancellation()
    guard attempt == revision, response.status == 200, response.body.count <= 64 * 1024,
          let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
          let access = json["access_token"] as? String, !access.isEmpty,
          let expires = json["expires_in"] as? Double, expires.isFinite, expires > 0 else { throw Failure.notAuthorized }
    if let scopes = json["scope"] as? String, !scopes.split(separator: " ").contains(Substring(Self.scope)) { throw Failure.notAuthorized }
    return (access, json["refresh_token"] as? String, expires)
  }

  private static func safeID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 512 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 95, 61].contains($0) }
  }

  private static func random(_ count: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: count)
    guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw Failure.unavailable }
    return urlSafe(Data(bytes))
  }

  private static func urlSafe(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }

  enum Failure: LocalizedError {
    case notConfigured, notConnected, notAuthorized, noCaptions, unavailable
    var errorDescription: String? {
      switch self {
      case .notConfigured: "このビルドではYouTubeへの接続を利用できません。お持ちの動画・字幕ファイルを追加してください。"
      case .notConnected: "YouTubeの字幕を自動取得する接続がありません。お持ちの動画・字幕ファイルを追加できます。"
      case .notAuthorized: "この動画の字幕を取得する権限がありません。動画を編集できるアカウントで接続するか、お持ちの字幕ファイルを追加してください。"
      case .noCaptions: "取得できる字幕がありません。お持ちの動画・字幕ファイルを追加してください。"
      case .unavailable: "字幕を取得できませんでした。通信状態を確認して再試行するか、お持ちのファイルを追加してください。"
      }
    }
  }

  private struct Tracks: Decodable {
    var items: [Track]
    struct Track: Decodable {
      var id: String
      var snippet: Snippet
      struct Snippet: Decodable { var language: String; var isDraft: Bool?; var status: String? }
    }
  }
}
