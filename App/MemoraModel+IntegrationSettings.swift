import Foundation

extension MemoraModel {
  func integrationIsEnabled(_ id: String) -> Bool { !disabledIntegrationIDs.contains(id) }

  func setIntegrationEnabled(_ id: String, enabled: Bool) {
    if id == "mcp", enabled != integrationIsEnabled(id) { mcpPermissionRevision = UUID() }
    if id == "gmail", enabled != integrationIsEnabled(id) { gmailPermissionRevision = UUID() }
    disabledIntegrationIDs.removeAll { $0 == id }
    if !enabled { disabledIntegrationIDs.append(id) }
    if id == "mcp", !enabled { activeMCPTools.removeAll() }
  }
}
