import Foundation

extension MemoraModel {
  func personPolicyIsCurrent(_ policy: AIPluginExecutionPolicy) -> Bool {
    guard let personID = policy.personID else { return true }
    guard aiPersonScopeID == personID, person(id: personID) != nil else { return false }
    return policy.recordIDs.isSubset(of: Set(meetings(withPerson: personID).map(\.id)))
      && policy.personTaskIDs.isSubset(of: Set(tasks.filter { PersonTaskAssociation.isAssigned($0, to: personID) }.map(\.id)))
  }
}
