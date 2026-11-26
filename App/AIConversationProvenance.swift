import Foundation

struct AIConversationProvenance: Codable, Hashable {
  var references: [AIRecordReference] = []
  var isComplete = true
  var workspaceID: String?
  var memoryFingerprint: String
  /// Set only by a cloud run that tracks authorization at the request boundary.
  var cloudReplayAuthorizationVersion: Int?

  func allowsCloudReplay(workspaceID: String?, memoryFingerprint: String,
                         resolve: (RecordPrivacyTarget) -> AIRecordReference?,
                         allows: (RecordPrivacyTarget) -> Bool) -> Bool {
    cloudReplayAuthorizationVersion == 1 && allowsReuse(workspaceID: workspaceID,
      memoryFingerprint: memoryFingerprint, resolve: resolve, allows: allows)
  }

  func allowsReuse(workspaceID: String?, memoryFingerprint: String,
                   resolve: (RecordPrivacyTarget) -> AIRecordReference?,
                   allows: (RecordPrivacyTarget) -> Bool) -> Bool {
    isComplete && references.count <= 256 && self.workspaceID == workspaceID
      && self.memoryFingerprint == memoryFingerprint
      && references.allSatisfy { allows($0.target) && resolve($0.target) == $0 }
  }
}
