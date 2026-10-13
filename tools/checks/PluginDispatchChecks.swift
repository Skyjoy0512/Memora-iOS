import Foundation

@main
struct PluginDispatchChecks {
  static func main() async throws {
    let schema = Data(#"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}"#.utf8)
    let tool = AIToolDefinition(id: "mcp_fixture", name: "search", summary: "offline fixture", inputSchema: schema, provider: .mcp,
      requiredPermissions: ["mcp:fixture"], risk: .read, isAvailable: true, isEnabled: true)
    var registry = AIToolRegistry()
    _ = registry.register(tool)
    let provider = FixtureIntegrationProvider(definition: tool)
    let policy = AIPluginExecutionPolicy(pluginIDs: ["mcp:fixture"], toolIDs: [tool.id], recordIDs: [], limitsRecordReads: true)
    let arguments = Data(#"{"query":"fixture"}"#.utf8)
    let result = try await registry.execute(tool.id, arguments: arguments, through: provider, policy: policy)
    precondition(result.text == "fixture result" && !result.isError)
    var wrongPolicy = policy; wrongPolicy.toolIDs = ["mcp_other"]
    do {
      _ = try await registry.execute(tool.id, arguments: arguments, through: provider, policy: wrongPolicy)
      preconditionFailure("scope escaped")
    } catch AIToolRegistry.DispatchFailure.scopeViolation {}
    do {
      _ = try await registry.execute(tool.id, arguments: Data(#"{"query":42}"#.utf8), through: provider, policy: policy)
      preconditionFailure("schema bypassed")
    } catch AIToolRegistry.DispatchFailure.invalidInput {}
    registry.tools[tool.id]?.requiredPermissions = ["mcp:another-account"]
    do {
      _ = try await registry.execute(tool.id, arguments: arguments, through: provider, policy: policy)
      preconditionFailure("provider identity mixed")
    } catch AIToolRegistry.DispatchFailure.providerMismatch {}
    registry.tools[tool.id] = tool
    registry.tools[tool.id]?.isEnabled = false
    do {
      _ = try await registry.execute(tool.id, arguments: arguments, through: provider, policy: policy)
      preconditionFailure("disabled tool ran")
    } catch AIToolRegistry.DispatchFailure.unavailable {}
    let count = await provider.calls
    precondition(count == 1)
    print("PluginDispatchChecks passed (real registry dispatch, mock provider, scope/schema/identity/disable rejection; no network)")
  }
}

private actor FixtureIntegrationProvider: IntegrationProvider {
  nonisolated let identifier = "mcp:fixture"
  var definition: AIToolDefinition
  var calls = 0
  init(definition: AIToolDefinition) { self.definition = definition }
  func tools() async throws -> [AIToolDefinition] { [definition] }
  func execute(_ tool: AIToolDefinition, arguments: Data) async throws -> IntegrationToolResult {
    calls += 1
    return IntegrationToolResult(text: "fixture result", isError: false)
  }
}
