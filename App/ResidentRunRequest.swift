import Foundation

/// Authorization captured before a queued or in-flight resident can suspend.
struct ResidentRunRequest {
  var agent: ResidentAgent
  var meetingID: UUID?
  var automatic: Bool
  var definitionRevision: UUID?
  var environmentRevision: UUID
  var workspaceGeneration: UUID
  var accessRevision: String
  var configurationRevision: UUID
  var registeredModelRevision: UUID
  var llm: LLMSelection
  var readToolNames: Set<String>
  var lastRunAt: Date?
}
