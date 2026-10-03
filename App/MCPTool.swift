import Foundation

/// A tool a connected MCP server offers, as the agent sees it.
struct MCPTool: Identifiable, Hashable, Sendable {
  var serverID: UUID
  var serverName: String
  var name: String
  var summary: String
  /// The tool's JSON schema, kept as data so the value stays Sendable.
  var inputSchema: Data
  /// The server says the tool only reads. Anything else asks first.
  var isReadOnly: Bool

  var id: String { agentName }

  /// The name the model calls it by: unique across servers and within the
  /// characters and length the model APIs allow.
  var agentName: String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    let tool = String(name.map { allowed.contains($0) ? $0 : "_" })
    let server = serverID.uuidString.prefix(6).lowercased()
    return String("mcp_\(server)_\(tool)".prefix(64))
  }

  var schemaObject: [String: Any] {
    (try? JSONSerialization.jsonObject(with: inputSchema)) as? [String: Any]
      ?? ["type": "object", "properties": [String: Any]()]
  }
}
