import Foundation

/// Which model an agent request runs on, decided once when it is sent.
@MainActor
enum AgentRunner {
  case cloud(CloudAgentSession)
  case onDevice

  var isOnDevice: Bool {
    if case .onDevice = self { return true }
    return false
  }
}
