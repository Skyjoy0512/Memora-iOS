import Foundation

struct ComposioProvider: IntegrationProvider {
  var identifier: String { "composio" }

  func tools() async throws -> [AIToolDefinition] { throw IntegrationConnectionError.backendNotConfigured }
  func execute(_ tool: AIToolDefinition, arguments: Data) async throws -> IntegrationToolResult {
    // The app has no authenticated integration backend. Never accept an admin key here.
    throw IntegrationConnectionError.backendNotConfigured
  }
}
