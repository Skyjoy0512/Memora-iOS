import Foundation
import CryptoKit
import MCP

actor MCPClient {
  static let shared = MCPClient()
  private var clients: [UUID: MCP.Client] = [:]
  private var generations: [UUID: Int] = [:]
  private var identities: [UUID: String] = [:]
  private var cachedTools: [UUID: (Date, [MCPTool])] = [:]

  func tools(on server: MCPServerConfig, token: String?) async throws -> [MCPTool] {
    let client = try await connected(server, token: token)
    if let cached = cachedTools[server.id], Date.now.timeIntervalSince(cached.0) < 300 { return cached.1 }
    do {
      var offered: [MCPTool] = [], cursor: String?
      var cursors = Set<String>()
      for _ in 0..<4 {
        let pageCursor = cursor
        let result = try await bounded(client: client) { try await client.listTools(cursor: pageCursor) }
        for tool in result.tools.prefix(40 - offered.count) {
          let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
          let schema = try encoder.encode(tool.inputSchema)
          guard schema.count <= 32 * 1024, tool.name.utf8.count <= 128 else { continue }
          offered.append(MCPTool(serverID: server.id, serverName: server.name, name: tool.name,
            summary: String((tool.description ?? tool.name).prefix(1_000)), inputSchema: schema,
            isReadOnly: tool.annotations.readOnlyHint == true))
        }
        cursor = result.nextCursor
        guard offered.count < 40, let next = cursor, cursors.insert(next).inserted else { break }
      }
      cachedTools[server.id] = (.now, offered)
      return offered
    } catch { await forget(server.id); throw safeError(error) }
  }

  func call(_ tool: String, arguments: Data, on server: MCPServerConfig, token: String?) async throws -> (text: String, isError: Bool) {
    guard arguments.count <= 32 * 1024 else { throw MCPClientError.malformed }
    let args = try JSONDecoder().decode([String: MCP.Value].self, from: arguments)
    let client = try await connected(server, token: token)
    do {
      let result = try await bounded(client: client) { try await client.callTool(name: tool, arguments: args) }
      var text = ""
      for item in result.content {
        if case .text(let value, _, _) = item { text += String(value.prefix(max(0, 20_000 - text.count))) + "\n" }
        if text.count >= 20_000 { break }
      }
      return (String(text.prefix(20_000)), result.isError ?? false)
    } catch { await forget(server.id); throw safeError(error) }
  }

  func reviewedCachedTools(on server: MCPServerConfig) -> [MCPTool] {
    guard clients[server.id] != nil else { return [] }
    return cachedTools[server.id]?.1 ?? []
  }

  func forget(_ id: UUID) async {
    generations[id, default: 0] += 1
    let client = clients.removeValue(forKey: id)
    identities[id] = nil; cachedTools[id] = nil
    await client?.disconnect()
  }

  private func connected(_ server: MCPServerConfig, token: String?) async throws -> MCP.Client {
    let generationBefore = generations[server.id, default: 0]
    let endpoint = try MCPConnectionPolicy.endpoint(server.url)
    let token = server.oauth == nil ? token : try await MCPOAuthClient.shared.accessToken(for: server)
    guard generations[server.id, default: 0] == generationBefore else { throw MCPClientError.unauthorized }
    guard MCPConnectionPolicy.tokenIsValid(token) else { throw MCPClientError.unauthorized }
    let digest = SHA256.hash(data: Data((endpoint.absoluteString + "\n" + (token ?? "")).utf8)).map { String(format: "%02x", $0) }.joined()
    if identities[server.id] == digest, let client = clients[server.id] { return client }
    await forget(server.id)
    let generation = generationBefore + 1
    guard generations[server.id] == generation else { throw MCPClientError.unauthorized }
    let transport = MCPBoundedHTTPTransport(endpoint: endpoint, token: token)
    let client = MCP.Client(name: "Memora", version: "1.0")
    do {
      let result = try await bounded(client: client) { try await client.connect(transport: transport) }
      await transport.setVersion(result.protocolVersion)
      guard generations[server.id] == generation else { throw MCPClientError.unauthorized }
      clients[server.id] = client; identities[server.id] = digest
      return client
    } catch { await client.disconnect(); throw safeError(error) }
  }

  private func safeError(_ error: Error) -> Error {
    if error is CancellationError { return CancellationError() }
    // Remote JSON-RPC errors may contain entire payloads or credentials.
    if let failure = error as? ExternalToolFailure { return failure }
    if let failure = error as? MCPClientError { return failure }
    if let failure = error as? MCPOAuthError { return failure }
    return MCPClientError.malformed
  }

  private func bounded<T: Sendable>(client: MCP.Client, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
          try await Task.sleep(for: .seconds(35))
          // SDK pending continuations also need disconnect, not just task cancellation.
          await client.disconnect()
          throw MCPClientError.timeout
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw MCPClientError.malformed }
        return value
      }
    } onCancel: {
      Task { await client.disconnect() }
    }
  }
}
