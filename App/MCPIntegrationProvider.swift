import Foundation

struct MCPIntegrationProvider: IntegrationProvider {
  var server: MCPServerConfig
  private var token: String?
  var identifier: String { "mcp:" + server.id.uuidString }

  init(server: MCPServerConfig, token: String?) {
    self.server = server
    self.token = token
  }

  func tools() async throws -> [AIToolDefinition] {
    guard server.isEnabled, server.reviewedEndpoint == server.url else { throw MCPClientError.unauthorized }
    return try await MCPClient.shared.tools(on: server, token: token).map { $0.definition }
  }

  func execute(_ tool: AIToolDefinition, arguments: Data) async throws -> IntegrationToolResult {
    guard server.isEnabled, server.reviewedEndpoint == server.url, tool.provider == .mcp,
          tool.requiredPermissions == [identifier], tool.isEnabled, tool.isAvailable,
          let object = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any],
          let schema = (try? JSONSerialization.jsonObject(with: tool.inputSchema)) as? [String: Any],
          ToolInputValidator.accepts(object, schema: schema) else { throw MCPClientError.unauthorized }
    let result = try await MCPClient.shared.call(tool.name, arguments: arguments, on: server, token: token)
    return IntegrationToolResult(text: result.text, isError: result.isError)
  }
}
