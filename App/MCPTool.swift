import Foundation
import CryptoKit

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
    let digest = SHA256.hash(data: Data((serverID.uuidString + "\n" + name).utf8)).map { String(format: "%02x", $0) }.joined()
    return "mcp_" + String(digest.prefix(24)) + "_" + String(tool.prefix(32))
  }

  var fingerprint: String {
    SHA256.hash(data: inputSchema + Data((name + summary + String(isReadOnly)).utf8)).map { String(format: "%02x", $0) }.joined()
  }

  var definition: AIToolDefinition {
    AIToolDefinition(id: agentName, name: name, summary: summary, inputSchema: inputSchema,
      provider: .mcp, requiredPermissions: ["mcp:" + serverID.uuidString],
      risk: isReadOnly ? .read : .sensitive, isAvailable: true, isEnabled: true)
  }

  var schemaObject: [String: Any] {
    (try? JSONSerialization.jsonObject(with: inputSchema)) as? [String: Any]
      ?? ["unsupportedSchema": true]
  }
}
