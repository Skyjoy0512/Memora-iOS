import Foundation

struct ResidentExecutionLimits: Codable, Hashable {
  var maximumModelTurns = 8
  var maximumToolCalls = 12
  var notifies = true
  var allowedToolNames: [String]?

  var modelTurnLimit: Int { min(8, max(1, maximumModelTurns)) }
  var toolCallLimit: Int { min(24, max(0, maximumToolCalls)) }

  func permits(_ name: String, availableReadTools: Set<String>) -> Bool {
    availableReadTools.contains(name) && (allowedToolNames?.contains(name) ?? true)
  }
}
