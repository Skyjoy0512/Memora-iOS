import Foundation

extension MemoraModel {
  func setSkillEnabled(_ id: String, enabled: Bool) {
    disabledSkillIDs.removeAll { $0 == id }
    if !enabled { disabledSkillIDs.append(id) }
  }

  func integrationIsEnabled(_ id: String) -> Bool { !disabledIntegrationIDs.contains(id) }

  func setIntegrationEnabled(_ id: String, enabled: Bool) {
    disabledIntegrationIDs.removeAll { $0 == id }
    if !enabled { disabledIntegrationIDs.append(id) }
    if id == "mcp", !enabled { activeMCPTools.removeAll() }
  }

  var enabledAgentTools: [AgentTool] {
    AgentTool.offered.filter { tool in
      if tool.needsGmail { return integrationIsEnabled("gmail") }
      if tool == .saveToNotion { return integrationIsEnabled("notion") && NotionService.isConfigured }
      if tool == .createCalendarEvent || tool == .readCalendar { return integrationIsEnabled("calendar") }
      return true
    }
  }

  func toolRegistry() -> AIToolRegistry {
    var registry = AIToolRegistry()
    for tool in enabledAgentTools {
      _ = registry.register(AIToolDefinition(id: "memora:" + tool.rawValue, name: tool.rawValue, summary: tool.summary,
        inputSchema: (try? JSONSerialization.data(withJSONObject: tool.inputSchema)) ?? Data(), provider: tool.needsGmail || tool == .saveToNotion ? .directAPI : .memora,
        requiredPermissions: [tool.needsApproval ? "memora.write" : "memora.read"],
        risk: tool.needsApproval ? .write : .read, isAvailable: true, isEnabled: true))
    }
    for tool in activeMCPTools.values {
      let server = mcpServers.first { $0.id == tool.serverID }
      var definition = tool.definition
      definition.isAvailable = server?.reviewedEndpoint == server?.url
      definition.isEnabled = server?.isEnabled == true && integrationIsEnabled("mcp")
      _ = registry.register(definition)
    }
    return registry
  }

  func consumeAgentToolCall(_ messageID: UUID) -> Bool {
    let count = agentToolCallCounts[messageID, default: 0]
    guard !Task.isCancelled, count < 24 else { return false }
    agentToolCallCounts[messageID] = count + 1
    return true
  }

  func consumeIntegrationCall(_ serverID: UUID) -> Bool {
    let day = Calendar.current.startOfDay(for: .now)
    var usage = integrationUsage.filter { $0.day == day }
    if let index = usage.firstIndex(where: { $0.serverID == serverID }) {
      guard usage[index].count < 50 else { return false }
      usage[index].count += 1
    } else { usage.append(IntegrationUsage(day: day, serverID: serverID, count: 1)) }
    guard persistNow(usage, forKey: "memora.integrations.usage.v1") else { return false }
    integrationUsage = usage
    return true
  }
}
