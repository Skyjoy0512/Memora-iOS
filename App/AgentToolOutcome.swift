import Foundation

/// What a tool run hands back to the model, and whether it went wrong.
struct AgentToolOutcome {
  var text: String
  var isError = false
}
