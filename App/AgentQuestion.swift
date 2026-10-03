import Foundation

/// One thing the agent needs to know before it can go on, with the choices it
/// offers. The person can also write their own answer.
struct AgentQuestion: Hashable {
  var text: String
  /// True when several choices may be picked.
  var allowsMultiple: Bool
  var options: [String]
}
