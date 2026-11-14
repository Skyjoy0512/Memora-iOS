import Foundation

/// A remote MCP server the agent may use, such as a Notion, Linear or company
/// server. Its access token, when it needs one, is kept in the keychain.
struct MCPServerConfig: Identifiable, Hashable, Codable, Sendable {
  var id: UUID
  var name: String
  var url: String
  var isEnabled = true
  var reviewedEndpoint: String? = nil
  var approvedReadToolFingerprints: [String: String]? = nil
  var hasUsageCharges: Bool? = nil
  var oauth: MCPOAuthSettings? = nil
  var preset: Preset? = nil

  enum Preset: String, Codable, CaseIterable, Sendable {
    case github, linear
    var name: String { self == .github ? "GitHub" : "Linear" }
    var endpoint: String {
      self == .github ? "https://api.githubcopilot.com/mcp/readonly" : "https://mcp.linear.app/mcp/readonly"
    }
    var tokenGuidance: String {
      self == .github
        ? "対象リポジトリのIssuesとPull requestsを読み取れるPersonal access tokenを入力してください。必要なリポジトリだけに権限を絞れます。"
        : "LinearのAPIキーを入力してください。Read権限だけを有効にし、必要なチームにアクセスを絞ってください。"
    }
    var documentationURL: URL {
      URL(string: self == .github ? "https://github.com/github/github-mcp-server#remote-github-mcp-server" : "https://linear.app/docs/mcp")!
    }
    func server() -> MCPServerConfig {
      MCPServerConfig(id: UUID(), name: name, url: endpoint, preset: self)
    }
  }

  // A provider label never turns an arbitrary endpoint into a trusted connector.
  var validatedPreset: Preset? {
    guard let preset, url == preset.endpoint, oauth == nil else { return nil }
    return preset
  }

  var presetHeaders: [String: String] {
    validatedPreset == .github ? ["X-MCP-Toolsets": "issues,pull_requests", "X-MCP-Readonly": "true"] : [:]
  }

  static func explicitServerIDs(pluginIDs: [String], servers: [Self]) -> Set<UUID> {
    Set(pluginIDs.flatMap { id -> [UUID] in
      if id.hasPrefix("mcp:"), let uuid = UUID(uuidString: String(id.dropFirst(4))) { return [uuid] }
      guard id.hasPrefix("service:"), let preset = Preset(rawValue: String(id.dropFirst(8))) else { return [] }
      return servers.filter { $0.validatedPreset == preset && $0.isEnabled && $0.reviewedEndpoint == $0.url }.map(\.id)
    })
  }

  var oauthAccount: String { "mcp.oauth.\(id.uuidString)" }

  var tokenAccount: String { "mcp.\(id.uuidString)" }
}
