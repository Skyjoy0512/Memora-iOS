import Foundation

struct AIToolRegistry {
  var tools: [String: AIToolDefinition] = [:]
  mutating func register(_ tool: AIToolDefinition) -> Bool {
    guard tools[tool.id] == nil else { return false }
    tools[tool.id] = tool
    return true
  }
  func permits(_ id: String, arguments: [String: Any]) -> Bool {
    guard let tool = tools[id] ?? tools["memora:" + id], tool.isEnabled, tool.isAvailable,
          let schema = (try? JSONSerialization.jsonObject(with: tool.inputSchema)) as? [String: Any] else { return false }
    return ToolInputValidator.accepts(arguments, schema: schema)
  }
}
