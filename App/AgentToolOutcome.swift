import Foundation

/// What a tool run hands back to the model, and whether it went wrong.
struct AgentToolOutcome {
  var text: String
  var isError = false
  var dataChange = DataChange.none

  /// External execution may have effects without a verifiable mutation receipt.
  enum DataChange: Sendable {
    case none
    case committed
    case unconfirmed
  }
}
