import Foundation

/// Talks to remote MCP servers over Streamable HTTP: JSON-RPC requests posted
/// to the server URL, answered as JSON or as a server-sent event stream.
/// One session per server is opened on first use and reused.
actor MCPClient {
  static let shared = MCPClient()

  private static let protocolVersion = "2025-06-18"
  private var sessions: [UUID: String] = [:]
  private var nextID = 1

  /// The tools a server offers.
  func tools(on server: MCPServerConfig, token: String?) async throws -> [MCPTool] {
    try await ensureSession(server, token: token)
    let result = try await request("tools/list", params: [:], server: server, token: token)
    let tools = result["tools"] as? [[String: Any]] ?? []
    return tools.compactMap { tool in
      guard let name = tool["name"] as? String else { return nil }
      let schema = tool["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [String: Any]()]
      let annotations = tool["annotations"] as? [String: Any]
      return MCPTool(
        serverID: server.id,
        serverName: server.name,
        name: name,
        summary: (tool["description"] as? String) ?? (annotations?["title"] as? String) ?? name,
        inputSchema: (try? JSONSerialization.data(withJSONObject: schema)) ?? Data(),
        isReadOnly: annotations?["readOnlyHint"] as? Bool ?? false
      )
    }
  }

  /// Calls a tool and returns its text content.
  func call(_ tool: String, arguments: Data, on server: MCPServerConfig, token: String?) async throws -> (text: String, isError: Bool) {
    try await ensureSession(server, token: token)
    let args = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
    let result = try await request("tools/call", params: ["name": tool, "arguments": args], server: server, token: token)
    let content = result["content"] as? [[String: Any]] ?? []
    var text = content.compactMap { item -> String? in
      switch item["type"] as? String {
      case "text": item["text"] as? String
      case "resource": ((item["resource"] as? [String: Any])?["text"] as? String)
      default: nil
      }
    }.joined(separator: "\n")
    if text.isEmpty, let structured = result["structuredContent"],
       let data = try? JSONSerialization.data(withJSONObject: structured) {
      text = String(decoding: data, as: UTF8.self)
    }
    return (text.isEmpty ? "（結果なし）" : text, result["isError"] as? Bool ?? false)
  }

  func forget(_ serverID: UUID) {
    sessions[serverID] = nil
  }

  // MARK: - Protocol

  private func ensureSession(_ server: MCPServerConfig, token: String?) async throws {
    guard sessions[server.id] == nil else { return }
    _ = try await request("initialize", params: [
      "protocolVersion": Self.protocolVersion,
      "capabilities": [String: Any](),
      "clientInfo": ["name": "Memora", "version": "1.0"]
    ], server: server, token: token, opening: true)
    try await notify("notifications/initialized", server: server, token: token)
  }

  private func request(
    _ method: String,
    params: [String: Any],
    server: MCPServerConfig,
    token: String?,
    opening: Bool = false
  ) async throws -> [String: Any] {
    let id = nextID
    nextID += 1
    let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    let (data, response) = try await post(body, server: server, token: token)

    if opening, let session = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
      sessions[server.id] = session
    } else if opening {
      // A server without sessions still answers; remember that it is open.
      sessions[server.id] = ""
    }
    if response.statusCode == 404, !opening, sessions[server.id] != nil {
      // The server dropped the session; open a new one once and retry.
      sessions[server.id] = nil
      try await ensureSession(server, token: token)
      return try await request(method, params: params, server: server, token: token)
    }
    if response.statusCode == 401 || response.statusCode == 403 { throw MCPClientError.unauthorized }
    guard (200..<300).contains(response.statusCode) else {
      throw MCPClientError.server("HTTP \(response.statusCode)")
    }

    let message = try Self.message(withID: id, in: data, contentType: response.value(forHTTPHeaderField: "Content-Type"))
    if let error = message["error"] as? [String: Any] {
      throw MCPClientError.server(error["message"] as? String ?? "不明なエラー")
    }
    guard let result = message["result"] as? [String: Any] else { throw MCPClientError.malformed }
    return result
  }

  private func notify(_ method: String, server: MCPServerConfig, token: String?) async throws {
    _ = try await post(["jsonrpc": "2.0", "method": method], server: server, token: token)
  }

  private func post(_ body: [String: Any], server: MCPServerConfig, token: String?) async throws -> (Data, HTTPURLResponse) {
    guard let url = URL(string: server.url.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme?.lowercased() == "https" else {
      throw MCPClientError.invalidURL
    }
    var request = URLRequest(url: url, timeoutInterval: 60)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
    if let session = sessions[server.id], !session.isEmpty {
      request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id")
    }
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw MCPClientError.malformed }
    return (data, http)
  }

  /// The JSON-RPC reply to `id`, from a JSON body or an event stream.
  private static func message(withID id: Int, in data: Data, contentType: String?) throws -> [String: Any] {
    if contentType?.contains("text/event-stream") == true {
      let text = String(decoding: data, as: UTF8.self)
      for event in text.components(separatedBy: "\n\n") {
        let payload = event
          .components(separatedBy: "\n")
          .filter { $0.hasPrefix("data:") }
          .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
          .joined(separator: "\n")
        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
        if (json["id"] as? Int) == id { return json }
      }
      throw MCPClientError.malformed
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw MCPClientError.malformed
    }
    return json
  }
}
