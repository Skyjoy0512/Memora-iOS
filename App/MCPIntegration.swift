import Foundation

/// Connection details for the MCP server that lets an outside assistant — such
/// as ChatGPT — read Memora. The server itself lives outside this app, so the
/// app only stores the endpoint, token, and scope.
enum MCPIntegration {
  static let tokenKey = "integration.mcp"
  static let serverURLKey = "memora.mcpServerURL"
  static let defaultServerURL = "https://mcp.memora.app/mcp"

  static var isConfigured: Bool {
    KeychainStore.has(tokenKey)
  }
}
