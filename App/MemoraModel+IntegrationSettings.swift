import Foundation

extension MemoraModel {
  func integrationHasConnection(_ id: String) -> Bool {
    switch id {
    case "gmail": GmailService.isConfigured && GmailService.shared.isConnected
    case "notion": NotionService.isConfigured
    case "calendar": CalendarService.access == .granted
    case "mcp": !activeMCPTools.isEmpty
    default: false
    }
  }

  func integrationIsEnabled(_ id: String) -> Bool { !disabledIntegrationIDs.contains(id) }

  func setIntegrationEnabled(_ id: String, enabled: Bool) {
    if id == "calendar", enabled != integrationIsEnabled(id) { invalidateAICalendarContext() }
    if id == "mcp", enabled != integrationIsEnabled(id) { mcpPermissionRevision = UUID() }
    if id == "gmail", enabled != integrationIsEnabled(id) { gmailPermissionRevision = UUID() }
    if id == "notion", enabled != integrationIsEnabled(id) { notionPermissionRevision = UUID() }
    disabledIntegrationIDs.removeAll { $0 == id }
    if !enabled { disabledIntegrationIDs.append(id) }
    if id == "mcp", !enabled { activeMCPTools.removeAll() }
  }
}
