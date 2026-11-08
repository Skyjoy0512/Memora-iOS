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
    var remaining = projectSources.filter { $0.id != id }
    // Drop links to the deleted source in the same write; never delete a note
    // or an attachment that merely referenced it.
    remaining = ProjectSource.pruningAttachmentLink(id, in: remaining)
    guard persistNow(remaining, forKey: StorageKey.projectSources) else { return false }
    sourcePreparationJobs.removeValue(forKey: id)?.task.cancel()
    if let job = projectWebFetchJobs.removeValue(forKey: id) {
      job.task.cancel()
      projectSourceProcessingIDs.remove(id)
    }
    projectSources = remaining
    invalidateProjectEvidence([.source(id)])
    discardSourceExtraction(for: source)
    let workspace = currentTeamID, generation = aiWorkspaceGeneration
    Task {
      guard workspace == currentTeamID, generation == aiWorkspaceGeneration else { return }
      let retained = Set(projectSources.flatMap(\.fileReferences)).union(retainedOfficeFileReferences)
      await ProjectSourceFiles.shared.remove(source.fileReferences.filter { !retained.contains($0) })
    }
    return true
  }
}
