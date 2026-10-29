import Foundation

extension AgentSessionBudget {
  /// A larger window is allowed to carry a larger request, within a hard cap
  /// so a mis-declared model cannot make the app assemble an enormous body.
  init(capabilities: ModelCapabilities, maximumRequests: Int = AgentSessionBudget.maximumRequests) {
    self.init()
    let bytes = max(Self.maximumRequestBytes,
      min(capabilities.maximumRequestBytes, 8 * 1024 * 1024))
    limitRequestBytes = bytes
    limitTotalRequestBytes = max(Self.maximumTotalRequestBytes, bytes * 4)
    limitRequests = max(4, min(maximumRequests, 32))
  }
}

extension AgentRunBudget {
  /// The run's request and output guards scaled to the selected model.
  convenience init(capabilities: ModelCapabilities) {
    self.init(requests: AgentSessionBudget(capabilities: capabilities),
      output: AgentOutputBudget(maximumTokens: min(capabilities.maximumOutputTokens * 2, 128_000)))
  }
}
