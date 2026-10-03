import Foundation

/// The questions the agent is waiting on, shown under its reply.
struct AgentQuestionRequest: Identifiable, Hashable {
  var id = UUID()
  var messageID: UUID
  var questions: [AgentQuestion]
}
