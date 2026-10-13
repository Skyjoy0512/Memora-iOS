import Foundation

struct AIToolDefinition: Identifiable, Sendable {
  var id: String
  var name: String
  var summary: String
  var inputSchema: Data
  var provider: Provider
  var requiredPermissions: [String]
  var risk: Risk
  var isAvailable: Bool
  var isEnabled: Bool
  enum Provider: String, Sendable { case memora, mcp, directAPI, composio }
  enum Risk: String, Sendable { case read, write, sensitive, destructive }
}
