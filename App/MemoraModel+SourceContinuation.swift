import Foundation

extension MemoraModel {
  @discardableResult
  func resumeProjectSource(_ id: UUID) -> Bool {
    queueProjectPDFPreparation(id, requiresContinuation: true)
  }

  @discardableResult
  func rereadProjectPDFSource(_ id: UUID) -> Bool {
    queueProjectPDFPreparation(id, requiresContinuation: false)
  }

  private func queueProjectPDFPreparation(_ id: UUID, requiresContinuation: Bool) -> Bool {
    guard !isRestoring, !isStoreProtected, currentTeamID == nil,
          sourcePreparationJobs[id] == nil, !projectSourceProcessingIDs.contains(id),
          var source = source(id: id), source.kind == .pdf,
          source.processingStatus != .pending, source.processingStatus != .processing,
          source.summaryStatus != .processing,
          LocalImportContext(projectID: source.projectID, in: self) != nil,
          let reference = source.localFileReference, let file = ProjectSourceFiles.resolve(reference),
          let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
          values.isRegularFile == true, values.isSymbolicLink != true,
          let bytes = values.fileSize, bytes <= ProjectSourceFiles.maximumFileBytes else { return false }
    if requiresContinuation {
      guard let page = source.resumePage ?? source.ocrFailedPages?.first, page > 0 else { return false }
    }
    // Keep the readable text and summary until the common job commits their
    // replacement. Local preparation never re-downloads this PDF's URL.
    source.processingStatus = .pending
    guard storeProjectSource(source) else { return false }
    return scheduleProjectSourcePreparation(id) != nil
  }
}
