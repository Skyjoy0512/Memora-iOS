import Foundation

/// No prompts, arguments, results or credentials enter diagnostic events.
enum AgentRunEvent: Equatable {
  case modelRequested(turn: Int)
  case toolStarted
  case toolFinished(isError: Bool)
  case finished(modelRequests: Int, toolCalls: Int, elapsedMilliseconds: Double)
}
