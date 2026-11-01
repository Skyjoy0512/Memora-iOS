import Foundation

extension MemoraModel {
  func prepareProjectSource(_ id: UUID) async {
    guard let job = scheduleProjectSourcePreparation(id) else { return }
    await job.value
  }

  @discardableResult
  func scheduleProjectSourcePreparation(_ id: UUID) -> Task<Void, Never>? {
    if let job = sourcePreparationJobs[id] { return job.task }
    guard ProjectSourcePreparationContext(id, in: self) != nil else { return nil }
    let attempt = UUID()
    let generation = aiWorkspaceGeneration
    let job = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.sourcePreparationJobs[id]?.id == attempt { self.sourcePreparationJobs.removeValue(forKey: id) }
      }
      guard self.aiWorkspaceGeneration == generation else { return }
      await self.performProjectSourcePreparation(id)
    }
    sourcePreparationJobs[id] = (attempt, job)
    return job
  }
}
