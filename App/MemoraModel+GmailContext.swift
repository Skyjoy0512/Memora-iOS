import Foundation

extension MemoraModel {
  func gmailResultsAreCurrent(_ messageID: UUID) -> Bool {
    guard let message = agentMessage(messageID) else { return false }
    return message.gmailResultAuthorizationIDs.allSatisfy {
      gmailResultAuthorizations[$0]?.bindingIsCurrent(in: self) == true
    }
  }

  func retainGmailResultAuthorization(_ context: GmailAgentReadContext, messageID: UUID) -> Bool {
    guard context.isCurrent(in: self), let message = agentMessage(messageID),
          message.gmailResultAuthorizationIDs.count < 24 else { return false }
    let id = UUID()
    gmailResultAuthorizations[id] = context
    updateAgentMessage(messageID) {
      $0.gmailResultAuthorizationIDs.insert(id)
      $0.cloudProvenance?.isComplete = false
    }
    return true
  }
}
