import Foundation

/// A remote MCP server the agent may use, such as a Notion, Linear or company
/// server. Its access token, when it needs one, is kept in the keychain.
struct MCPServerConfig: Identifiable, Hashable, Codable {
  var id: UUID
  var name: String
  var url: String
  var isEnabled = true

  var tokenAccount: String { "mcp.\(id.uuidString)" }
}
