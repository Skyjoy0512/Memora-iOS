import Foundation
import FoundationModels

/// One agent tool offered to Apple's on-device model. Its schema is built from
/// the same `AgentTool` definition the cloud models get, and a call is handed
/// to the same code, so both engines read and change records identically,
/// approval cards included.
@available(iOS 26.0, *)
struct OnDeviceAgentTool: Tool {
  /// Runs a tool by name with its arguments as JSON, and returns the text for
  /// the model.
  typealias Perform = @MainActor @Sendable (_ name: String, _ argumentsJSON: String) async -> String

  let tool: AgentTool
  let parameters: GenerationSchema
  let perform: Perform

  var name: String { tool.rawValue }
  var description: String { tool.summary }

  nonisolated func call(arguments: GeneratedContent) async throws -> String {
    await perform(tool.rawValue, arguments.jsonString)
  }

  /// The tools for the on-device model. A tool whose schema cannot be built is
  /// left out rather than stopping the others.
  static func all(_ tools: [AgentTool], perform: @escaping Perform) -> [OnDeviceAgentTool] {
    tools.compactMap { tool in
      guard let schema = try? GenerationSchema(
        root: dynamicSchema(name: tool.rawValue, json: tool.inputSchema),
        dependencies: []
      ) else { return nil }
      return OnDeviceAgentTool(tool: tool, parameters: schema, perform: perform)
    }
  }

  /// Converts the JSON schema subset `AgentTool` uses: objects, arrays,
  /// strings, integers and booleans.
  private static func dynamicSchema(name: String, json: [String: Any]) -> DynamicGenerationSchema {
    switch json["type"] as? String {
    case "object":
      let properties = json["properties"] as? [String: [String: Any]] ?? [:]
      let required = json["required"] as? [String] ?? []
      // Required fields first, in the order written, so the model fills the
      // title before the body.
      let order = required + properties.keys.filter { !required.contains($0) }.sorted()
      return DynamicGenerationSchema(
        name: name,
        description: json["description"] as? String,
        properties: order.compactMap { key in
          guard let property = properties[key] else { return nil }
          return DynamicGenerationSchema.Property(
            name: key,
            description: property["description"] as? String,
            schema: dynamicSchema(name: "\(name)_\(key)", json: property),
            isOptional: !required.contains(key)
          )
        }
      )
    case "array":
      let items = json["items"] as? [String: Any] ?? ["type": "string"]
      return DynamicGenerationSchema(arrayOf: dynamicSchema(name: "\(name)_item", json: items))
    case "integer":
      return DynamicGenerationSchema(type: Int.self)
    case "boolean":
      return DynamicGenerationSchema(type: Bool.self)
    default:
      return DynamicGenerationSchema(type: String.self)
    }
  }
}
