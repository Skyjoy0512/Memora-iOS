import Foundation

protocol IntegrationProvider: Sendable {
  var identifier: String { get }
  func tools() async throws -> [AIToolDefinition]
  func execute(_ tool: AIToolDefinition, arguments: Data) async throws -> IntegrationToolResult
}
