import Foundation

extension MemoraModel {
  @discardableResult
  func resumeProjectSource(_ id: UUID) -> Bool {
    guard !isRestoring, !isStoreProtected, currentTeamID == nil,
          sourcePreparationJobs[id] == nil, !projectSourceProcessingIDs.contains(id),
          var source = source(id: id), source.kind == .pdf,
          source.processingStatus != .pending, source.processingStatus != .processing,
          let page = source.resumePage, page > 0, source.localFileReference != nil else { return false }
    source.processingStatus = .pending
    guard storeProjectSource(source) else { return false }
    return scheduleProjectSourcePreparation(id) != nil
  }

}
