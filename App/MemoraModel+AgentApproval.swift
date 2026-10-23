import Foundation

extension MemoraModel {
  /// Shows the change on the reply and waits for the person to decide.
  func requestAgentApproval(_ approval: AgentApproval, changesData: Bool = true) async -> Bool {
    guard !Task.isCancelled, gmailResultsAreCurrent(approval.messageID) else { return false }
    if agentMessage(approval.messageID)?.cloudProvenance != nil, !isCloudSessionAuthorized(approval.messageID) { return false }
    let approved = await agentApprovalWaiter.wait(id: approval.id) {
      pendingAgentApproval = approval
    } dismiss: { [weak self] in
      if self?.pendingAgentApproval?.id == approval.id { self?.pendingAgentApproval = nil }
    }
    guard !Task.isCancelled, gmailResultsAreCurrent(approval.messageID) else { return false }
    if agentMessage(approval.messageID)?.cloudProvenance != nil, !isCloudSessionAuthorized(approval.messageID) { return false }
    if approved == true && changesData {
      updateAgentMessage(approval.messageID) { $0.didChangeData = true }
    }
    return approved == true
  }
}
