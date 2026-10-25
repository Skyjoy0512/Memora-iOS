import Foundation

actor MCPOAuthClient {
  static let shared = MCPOAuthClient()
  private var refreshes: [String: (id: UUID, task: Task<String, Error>)] = [:]
  private var http: MCPPinnedHTTP

  init(http: MCPPinnedHTTP = .init()) { self.http = http }

  func cancel(_ id: UUID) {
    let prefix = id.uuidString + ":"
    for key in refreshes.keys.filter({ $0.hasPrefix(prefix) }) { refreshes.removeValue(forKey: key)?.task.cancel() }
  }

  func exchange(code: String, verifier: String, server: MCPServerConfig) async throws -> MCPOAuthCredential {
    guard let settings = server.oauth else { throw MCPOAuthError.configuration }
    let identity = try MCPOAuthPolicy.identity(endpoint: server.url, settings: settings)
    let values = ["grant_type": "authorization_code", "code": code, "code_verifier": verifier,
      "client_id": settings.clientID, "redirect_uri": MCPOAuthPolicy.redirectURI.absoluteString,
      "resource": try MCPConnectionPolicy.endpoint(server.url).absoluteString]
    let data = try await Self.request(settings: settings, values: values, http: http)
    return try MCPOAuthCredential.decodeResponse(data, identity: identity,
      requestedScopes: MCPOAuthPolicy.scopeSet(settings.scopes))
  }

  func accessToken(for server: MCPServerConfig) async throws -> String {
    guard let settings = server.oauth else { throw MCPOAuthError.configuration }
    let identity = try MCPOAuthPolicy.identity(endpoint: server.url, settings: settings)
    guard let raw = KeychainStore.string(forKey: server.oauthAccount),
          let credential = try? JSONDecoder().decode(MCPOAuthCredential.self, from: Data(raw.utf8)),
          credential.identity == identity else { throw MCPOAuthError.reauthentication }
    if credential.expiresAt.timeIntervalSinceNow > 30 { return credential.accessToken }
    guard let refresh = credential.refreshToken else { throw MCPOAuthError.reauthentication }
    let key = server.id.uuidString + ":" + identity
    if let existing = refreshes[key] {
      return try await withTaskCancellationHandler { try await existing.task.value } onCancel: { existing.task.cancel() }
    }
    let requestID = UUID()
    let http = http
    let task = Task<String, Error> {
      let data = try await Self.request(settings: settings, values: ["grant_type": "refresh_token",
        "refresh_token": refresh, "client_id": settings.clientID, "resource": server.url,
        "scope": credential.scopes.sorted().joined(separator: " ")], http: http)
      let renewed = try MCPOAuthCredential.decodeResponse(data, identity: identity,
        requestedScopes: credential.scopes, previous: credential)
      try Task.checkCancellation()
      // A disconnect or newer authorization must win over an in-flight refresh.
      guard KeychainStore.string(forKey: server.oauthAccount) == raw else { throw MCPOAuthError.reauthentication }
      let encoded = String(decoding: try JSONEncoder().encode(renewed), as: UTF8.self)
      guard KeychainStore.replaceIfUnchanged(encoded, expected: raw, forKey: server.oauthAccount) else { throw MCPOAuthError.storage }
      return renewed.accessToken
    }
    refreshes[key] = (requestID, task)
    defer { if refreshes[key]?.id == requestID { refreshes[key] = nil } }
    return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
  }

  private static func request(settings: MCPOAuthSettings, values: [String: String], http: MCPPinnedHTTP) async throws -> Data {
    let validated = try MCPOAuthPolicy.validated(settings)
    let endpoint = try MCPConnectionPolicy.endpoint(validated.tokenURL)
    return try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        let body = MCPOAuthPolicy.form(values)
        guard body.count <= 32 * 1024 else { throw MCPOAuthError.configuration }
        let response = try await http.post(endpoint: endpoint, body: body,
          headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
          maximumResponseBytes: 128 * 1024, contentTypes: ["application/json"], emptyStatuses: [])
        guard response.status == 200 else { throw MCPOAuthError.tokenResponse }
        return response.body
      }
      group.addTask { try await Task.sleep(for: .seconds(35)); throw MCPClientError.timeout }
      defer { group.cancelAll() }
      guard let data = try await group.next() else { throw MCPOAuthError.tokenResponse }
      return data
    }
  }
}
