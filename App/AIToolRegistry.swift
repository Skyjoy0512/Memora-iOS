import Foundation

struct AIToolRegistry {
  var tools: [String: AIToolDefinition] = [:]
  mutating func register(_ tool: AIToolDefinition) -> Bool {
    guard tools[tool.id] == nil else { return false }
    tools[tool.id] = tool
    return true
  }
  func permits(_ id: String, arguments: [String: Any], policy: AIPluginExecutionPolicy? = nil) -> Bool {
    guard policy?.permits(id, arguments: arguments) ?? true else { return false }
    guard let tool = tools[id] ?? tools["memora:" + id], tool.isEnabled, tool.isAvailable,
          let schema = (try? JSONSerialization.jsonObject(with: tool.inputSchema)) as? [String: Any] else { return false }
    return ToolInputValidator.accepts(arguments, schema: schema)
  }

  /// Called after approval and the existing call budget; rechecks current grants before dispatch.
  func execute(_ id: String, arguments: Data, through provider: any IntegrationProvider,
               policy: AIPluginExecutionPolicy? = nil) async throws -> IntegrationToolResult {
    guard let tool = tools[id], tool.isAvailable, tool.isEnabled else { throw DispatchFailure.unavailable }
    guard tool.requiredPermissions == [provider.identifier] else { throw DispatchFailure.providerMismatch }
    guard let object = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] else { throw DispatchFailure.invalidInput }
    guard policy?.permits(id, arguments: object) ?? true else { throw DispatchFailure.scopeViolation }
    guard permits(id, arguments: object, policy: policy) else { throw DispatchFailure.invalidInput }
    return try await provider.execute(tool, arguments: arguments)
  }

  enum DispatchFailure: Error { case unavailable, providerMismatch, invalidInput, scopeViolation }
}
