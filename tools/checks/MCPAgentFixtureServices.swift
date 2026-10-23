import Foundation

@MainActor
enum KeychainStore {
  static var values: [String: String] = [:]
  static func string(forKey key: String) -> String? { values[key] }
  static func has(_ key: String) -> Bool { values[key] != nil }
  static func set(_ value: String?, forKey key: String) -> Bool { values[key] = value; return true }
}

@MainActor final class MCPClient {
  static let shared = MCPClient()
  var offered: [UUID: [MCPTool]] = [:]
  var listCalls: [UUID] = []
  var cacheReads: [UUID] = []
  var dispatched = 0
  var beforeList: ((UUID) async -> Void)?
  var beforeDispatch: (() async -> Void)?
  var afterDispatch: (() async -> Void)?
  var failure: Error?
  var isError = false

  func reset() {
    offered = [:]; listCalls = []; cacheReads = []; dispatched = 0
    beforeList = nil; beforeDispatch = nil; afterDispatch = nil; failure = nil; isError = false
    KeychainStore.values = [:]
  }
  func forget(_ id: UUID) async {}
  func tools(on server: MCPServerConfig, token: String?,
    isAuthorized: @escaping @MainActor @Sendable () -> Bool = { true }
  ) async throws -> [MCPTool] {
    guard isAuthorized() else { throw MCPClientError.unauthorized }
    listCalls.append(server.id)
    await beforeList?(server.id)
    if let failure { throw failure }
    return offered[server.id] ?? []
  }
  func reviewedCachedTools(on server: MCPServerConfig) async -> [MCPTool] {
    cacheReads.append(server.id)
    return offered[server.id] ?? []
  }
  func call(_ tool: String, arguments: Data, on server: MCPServerConfig, token: String?,
    isAuthorized: @escaping @MainActor @Sendable () -> Bool
  ) async throws -> (text: String, isError: Bool) {
    guard isAuthorized() else { throw MCPClientError.unauthorized }
    // Models SDK connection preparation. No real SDK, DNS, TLS or OAuth runs.
    await beforeDispatch?()
    guard isAuthorized() else { throw MCPClientError.unauthorized }
    dispatched += 1
    await afterDispatch?()
    if let failure { throw failure }
    // Intentionally return even when revoked: the production model must discard it.
    return ("PRIVATE_FIXTURE_RESULT", isError)
  }
}
@MainActor final class MCPOAuthClient {
  static let shared = MCPOAuthClient()
  func cancel(_ id: UUID) async {}
}
@MainActor final class GmailService {
  static let shared = GmailService()
  static let isConfigured = false
  var isConnected = false
}
@MainActor enum NotionService { static let isConfigured = false }
enum WebResearchClient { static let keyName = "no-real-web-key" }
