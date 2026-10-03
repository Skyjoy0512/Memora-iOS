import Foundation

/// One reply from the model: what it wrote, and the tools it wants to run
/// before it goes on. No tool calls means the answer is finished.
struct AgentTurn {
  var text: String
  var toolCalls: [AgentToolCall]
  /// The reasoning the model returned with this turn, when the provider sends
  /// it (Claude's thinking, DeepSeek's reasoning). Empty when it does not.
  var reasoning = ""
}
