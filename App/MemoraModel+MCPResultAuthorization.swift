import Foundation

extension MemoraModel {
  func mcpResultsAreCurrent(_ messageID: UUID) -> Bool {
    guard let message = agentMessage(messageID) else { return false }
    return message.mcpResultAuthorizationIDs.allSatisfy {
      mcpResultAuthorizations[$0]?.isCurrent(in: self) == true
    }
  }

  func retainMCPResultAuthorization(_ authorization: MCPResultAuthorization, messageID: UUID) -> Bool {
    guard authorization.isCurrent(in: self), let message = agentMessage(messageID),
          message.mcpResultAuthorizationIDs.count < 24 else { return false }
    let id = UUID()
    mcpResultAuthorizations[id] = authorization
    updateAgentMessage(messageID) {
      $0.mcpResultAuthorizationIDs.insert(id)
      // Reopening history must not restore this run's external-data grants.
      $0.cloudProvenance?.isComplete = false
    }
    return true
  }
}
