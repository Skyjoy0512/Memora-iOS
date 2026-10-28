import Foundation

extension MemoraModel {
  @discardableResult
  func detachProjectSource(_ id: UUID) -> Bool {
    guard var source = source(id: id) else { return false }
    source.projectID = nil
    source.updatedAt = .now
    return storeProjectSource(source)
  }

  @discardableResult
  func deleteProjectSource(_ id: UUID) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), let source = source(id: id) else { return false }
    let remaining = projectSources.filter { $0.id != id }
    guard persistNow(remaining, forKey: StorageKey.projectSources) else { return false }
    if let job = projectWebFetchJobs.removeValue(forKey: id) {
      job.task.cancel()
      projectSourceProcessingIDs.remove(id)
    }
    projectSources = remaining
    invalidateProjectEvidence([.source(id)])
    let workspace = currentTeamID, generation = aiWorkspaceGeneration
    Task {
      guard workspace == currentTeamID, generation == aiWorkspaceGeneration else { return }
      let retained = Set(projectSources.flatMap(\.fileReferences)).union(retainedOfficeFileReferences)
      await ProjectSourceFiles.shared.remove(source.fileReferences.filter { !retained.contains($0) })
    }
    return true
  }
}
