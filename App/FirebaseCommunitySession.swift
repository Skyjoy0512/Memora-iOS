import Foundation
import Observation

@MainActor @Observable
final class FirebaseCommunitySession {
  static let shared = FirebaseCommunitySession()
  private(set) var email: String?
  private(set) var userID: String?
  private var accessToken: String?
  private var expiresAt = Date.distantPast
  private(set) var generation = UUID()
  @ObservationIgnored private var refreshing: Task<String, Error>?
  var isSignedIn: Bool { accessToken != nil || (!Self.apiKey.isEmpty && KeychainStore.has(credentialKey)) }
  nonisolated static var apiKey: String { Bundle.main.object(forInfoDictionaryKey: "MemoraFirebaseAPIKey") as? String ?? "" }
  private var credentialKey: String { "marketplace.firebase.refresh." + Self.apiKey }

  func signIn(email: String, password: String, create: Bool) async throws {
    guard !Self.apiKey.isEmpty else { throw CommunityError.unconfigured }
    generation = UUID(); refreshing?.cancel(); refreshing = nil
    let expected = generation
    let route = create ? "accounts:signUp" : "accounts:signInWithPassword"
    let data = try await request(route, body: ["email":email,"password":password,"returnSecureToken":true])
    guard expected == generation, let token = data["idToken"] as? String, let refresh = data["refreshToken"] as? String,
          KeychainStore.set(refresh, forKey: credentialKey) else { throw CommunityError.loginRequired }
    accessToken = token; userID = data["localId"] as? String; self.email = email; expiresAt = Date.now.addingTimeInterval(3500)
    if create { _ = try await request("accounts:sendOobCode", body: ["requestType":"VERIFY_EMAIL","idToken":token]) }
  }

  func token() async throws -> String {
    if let accessToken, expiresAt > .now { return accessToken }
    if let refreshing { return try await refreshing.value }
    let expected = generation
    let task = Task { try await refreshToken() }
    refreshing = task
    defer { if expected == generation { refreshing = nil } }
    return try await task.value
  }

  private func refreshToken() async throws -> String {
    guard !Self.apiKey.isEmpty, let refresh = KeychainStore.string(forKey: credentialKey) else { throw CommunityError.loginRequired }
    let expected = generation
    var request = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Self.apiKey)")!)
    request.httpMethod = "POST"; request.timeoutInterval = 20
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var form = URLComponents(); form.queryItems = [URLQueryItem(name:"grant_type",value:"refresh_token"),URLQueryItem(name:"refresh_token",value:refresh)]
    request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
    let (bytes,response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, expected == generation,
          let object = try JSONSerialization.jsonObject(with: bytes) as? [String:Any],
          let token = object["id_token"] as? String, let replacement = object["refresh_token"] as? String,
          KeychainStore.replaceIfUnchanged(replacement, expected: refresh, forKey: credentialKey) else { throw CommunityError.loginRequired }
    userID = object["user_id"] as? String
    accessToken = token; expiresAt = Date.now.addingTimeInterval(3500)
    return token
  }

  func refreshVerification() async throws {
    expiresAt = .distantPast
    _ = try await token()
  }

  func signOut() throws {
    guard KeychainStore.set(nil, forKey: credentialKey) else { throw CommunityError.saveFailed }
    generation = UUID(); refreshing?.cancel(); refreshing = nil; accessToken = nil; email = nil; userID = nil; expiresAt = .distantPast
  }

  private func request(_ route: String, body: [String:Any]) async throws -> [String:Any] {
    var request = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/\(route)?key=\(Self.apiKey)")!)
    request.httpMethod = "POST"; request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (bytes,response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let result = try JSONSerialization.jsonObject(with: bytes) as? [String:Any] else {
      throw CommunityError.server("ログインできません。メールアドレス・パスワードと接続状態を確認してください。")
    }
    return result
  }
}
