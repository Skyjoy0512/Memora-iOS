import Foundation

extension MemoraModel {
  /// This reconciles current state, never a suspended job's snapshot. It changes
  /// only orphaned status/notice fields and never resumes a read or removes files.
  @discardableResult
  func recoverInterruptedProjectSources() -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected else { return false }
    var candidate = projectSources
    var changed: [ProjectCitation.Target] = []
    for index in candidate.indices where candidate[index].processingStatus == .processing &&
      !projectSourceProcessingIDs.contains(candidate[index].id) {
      candidate[index].processingStatus = candidate[index].kind == .youtube ? .unavailable : .failed
      candidate[index].errorInformation = "処理は中断されました。ソースは保持しています。必要に応じて再試行してください。自動では再開しません。"
      changed.append(.source(candidate[index].id))
    }
    guard !changed.isEmpty else { return true }
    guard persistNow(candidate, forKey: StorageKey.projectSources) else { return false }
    projectSources = candidate
    invalidateProjectEvidence(changed)
    return true
  }
}
