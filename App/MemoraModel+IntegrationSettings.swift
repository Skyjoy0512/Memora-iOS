import Foundation

extension MemoraModel {
  func integrationHasConnection(_ id: String) -> Bool {
    switch id {
    case "gmail": GmailService.isConfigured && GmailService.shared.isConnected
    case "notion": NotionService.isConfigured
    case "calendar": CalendarService.access == .granted
    case "mcp": mcpServers.contains { mcpConnectionIsReviewed($0) }
    case "github", "linear": mcpServers.contains { $0.validatedPreset?.rawValue == id && mcpConnectionIsReviewed($0) }
    default: false
    }
  }

  func integrationIsEnabled(_ id: String) -> Bool { !disabledIntegrationIDs.contains(id) }

  func mcpConnectionIsReviewed(_ server: MCPServerConfig) -> Bool {
    guard server.reviewedEndpoint == server.url, server.preset == nil || server.validatedPreset != nil else { return false }
    if server.validatedPreset != nil { return KeychainStore.has(server.tokenAccount) }
    return server.oauth == nil || KeychainStore.has(server.oauthAccount)
  }

  func mcpServerIsEnabled(_ server: MCPServerConfig) -> Bool {
    server.isEnabled && integrationIsEnabled("mcp") && (server.preset == nil || server.validatedPreset != nil)
      && (server.validatedPreset.map { integrationIsEnabled($0.rawValue) } ?? true)
  }

  func setIntegrationEnabled(_ id: String, enabled: Bool) {
    if id == "calendar", enabled != integrationIsEnabled(id) { invalidateAICalendarContext() }
    if ["mcp", "github", "linear"].contains(id), enabled != integrationIsEnabled(id) { mcpPermissionRevision = UUID() }
    if id == "gmail", enabled != integrationIsEnabled(id) { gmailPermissionRevision = UUID() }
    if id == "notion", enabled != integrationIsEnabled(id) { notionPermissionRevision = UUID() }
    disabledIntegrationIDs.removeAll { $0 == id }
    if !enabled { disabledIntegrationIDs.append(id) }
    if id == "mcp", !enabled { activeMCPTools.removeAll() }
    if let preset = MCPServerConfig.Preset(rawValue: id), !enabled {
      let ids = Set(mcpServers.filter { $0.validatedPreset == preset }.map(\.id))
      activeMCPTools = activeMCPTools.filter { !ids.contains($0.value.serverID) }
    }
  }
}
