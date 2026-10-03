import Foundation

// Remote MCP servers as tools for the Ask AI agent: Notion, Linear, a company
// server — whatever the person connects. Tools the server marks read-only run
// straight away; every other one waits for the approval card, since Memora
// cannot know what it changes.
extension MemoraModel {
  func saveMCPServer(_ server: MCPServerConfig, token: String?) {
    if let token {
      KeychainStore.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: server.tokenAccount)
    }
    if let index = mcpServers.firstIndex(where: { $0.id == server.id }) {
      mcpServers[index] = server
    } else {
      mcpServers.append(server)
    }
    Task { await MCPClient.shared.forget(server.id) }
  }

  func deleteMCPServer(_ id: UUID) {
    guard let server = mcpServers.first(where: { $0.id == id }) else { return }
    KeychainStore.set(nil, forKey: server.tokenAccount)
    mcpServers.removeAll { $0.id == id }
    Task { await MCPClient.shared.forget(id) }
  }

  /// Connects to a server and lists its tools, to check the settings.
  func checkMCPServer(_ server: MCPServerConfig) async throws -> [MCPTool] {
    await MCPClient.shared.forget(server.id)
    return try await MCPClient.shared.tools(
      on: server,
      token: KeychainStore.string(forKey: server.tokenAccount)
    )
  }

  /// The tools of every enabled server, for one agent run. A server that does
  /// not answer is left out rather than stopping the agent.
  func loadMCPToolsForAgent() async -> [MCPTool] {
    var tools: [MCPTool] = []
    for server in mcpServers where server.isEnabled {
      let token = KeychainStore.string(forKey: server.tokenAccount)
      if let offered = try? await MCPClient.shared.tools(on: server, token: token) {
        tools.append(contentsOf: offered.prefix(40))
      }
    }
    activeMCPTools = Dictionary(tools.map { ($0.agentName, $0) }, uniquingKeysWith: { first, _ in first })
    return tools
  }

  func performMCPTool(_ tool: MCPTool, call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    guard let server = mcpServers.first(where: { $0.id == tool.serverID }) else {
      return AgentToolOutcome(text: "接続先が見つかりません。", isError: true)
    }
    let title = "\(tool.serverName)：\(tool.name)"
    let arguments = (try? JSONSerialization.data(withJSONObject: call.arguments)) ?? Data("{}".utf8)

    let stepID: UUID
    if tool.isReadOnly {
      stepID = beginAgentStep(AgentStep(icon: .plugsConnected, title: title), on: messageID)
    } else {
      stepID = beginAgentStep(AgentStep(icon: .plugsConnected, title: title, detail: "確認待ち"), on: messageID)
      let summary = String(decoding: arguments, as: UTF8.self)
      let approved = await requestAgentApproval(AgentApproval(
        messageID: messageID,
        icon: .plugsConnected,
        title: "\(tool.serverName)で「\(tool.name)」を実行",
        lines: [tool.summary, String(summary.prefix(300))].filter { !$0.isEmpty },
        confirmTitle: "実行"
      ))
      guard approved, !Task.isCancelled else {
        finishAgentStep(stepID, on: messageID, state: .declined, detail: "取りやめました")
        return AgentToolOutcome(text: "利用者がこの操作を承認しませんでした。同じ操作を繰り返さないでください。")
      }
      finishAgentStep(stepID, on: messageID, state: .running, detail: "")
    }

    do {
      let result = try await MCPClient.shared.call(
        tool.name,
        arguments: arguments,
        on: server,
        token: KeychainStore.string(forKey: server.tokenAccount)
      )
      finishAgentStep(stepID, on: messageID, state: result.isError ? .failed : .done, detail: result.isError ? "エラー" : nil)
      return AgentToolOutcome(text: String(result.text.prefix(20_000)), isError: result.isError)
    } catch {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "接続できませんでした")
      return AgentToolOutcome(text: error.localizedDescription, isError: true)
    }
  }
}
