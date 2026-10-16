import Foundation

extension MemoraModel {
  func allowsPersonAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected, let person = person(id: id) else { return false }
    guard purpose == .cloudAI || purpose == .automaticAgent || purpose == .onDeviceAI else { return false }
    return RecordAccessPolicy.allows(person.effectivePrivacy, purpose: purpose)
  }
}
