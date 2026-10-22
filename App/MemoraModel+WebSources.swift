import Foundation

extension MemoraModel {
  /// Called by the person's fetch action only. Saving or reopening a URL never
  /// fetches it; an interrupted network operation is not persisted or replayed.
  @discardableResult
  func fetchProjectWebSource(_ id: UUID, fetcher: WebSourceFetcher = WebSourceFetcher(),
    writeText: ((Data) async throws -> String)? = nil
  ) async -> Bool {
    guard let context = ProjectSourcePreparationContext(id, in: self),
          context.source.kind == .web, let url = context.source.originalURL,
          !projectSourceProcessingIDs.contains(id), projectWebFetchJobs[id] == nil else { return false }
    let original = context.source
    let operationID = UUID()
    let job = Task { try await fetcher.fetch(url) }
    projectWebFetchJobs[id] = (operationID, job)
    projectSourceProcessingIDs.insert(id)
    defer {
      if projectWebFetchJobs[id]?.id == operationID {
        projectWebFetchJobs.removeValue(forKey: id)
        projectSourceProcessingIDs.remove(id)
        recoverInterruptedProjectSources()
      }
    }
    func current(allowsCancellation: Bool = false) -> ProjectSource? {
      guard context.isCurrent(in: self, allowsCancellation: allowsCancellation),
            projectWebFetchJobs[id]?.id == operationID,
            let source = source(id: id) else { return nil }
      return source
    }
    var created: String?
    do {
      let result = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
      try Task.checkCancellation()
      guard !job.isCancelled, current() != nil else { return false }
      let bytes = try JSONEncoder().encode(result.content.blocks)
      guard !result.content.blocks.isEmpty, bytes.count <= ProjectSourceTextReader.maximumBytes else { throw WebSourceFailure.tooLarge }
      let reference: String
      if let writeText { reference = try await writeText(bytes) }
      else { reference = try await ProjectSourceFiles.shared.write(bytes, extension: "json") }
      created = reference
      try Task.checkCancellation()
      guard !job.isCancelled, var source = current() else {
        await ProjectSourceFiles.shared.remove([reference]); return false
      }
      let old = source.extractedTextReference
      if source.title == original.title, let title = result.content.title { source.title = title }
      source.extractedTextReference = reference
      source.processingStatus = .ready
      source.textCoverage = .partial
      source.updatedAt = result.fetchedAt
      source.errorInformation = result.content.notice
      var metadata = source.metadata ?? [:]
      metadata["webFetchedAt"] = ISO8601DateFormatter().string(from: result.fetchedAt)
      metadata["webFinalURL"] = result.finalURL.absoluteString
      source.metadata = metadata
      guard storeProjectSource(source) else {
        await ProjectSourceFiles.shared.remove([reference]); return false
      }
      created = nil
      if let old, !projectSources.contains(where: { $0.fileReferences.contains(old) }) {
        await ProjectSourceFiles.shared.remove([old])
      }
      return true
    } catch {
      if let created { await ProjectSourceFiles.shared.remove([created]) }
      guard var source = current(allowsCancellation: true) else { return false }
      let reason: String
      if error is CancellationError { reason = "本文の取得を停止しました。再取得は操作した場合だけ行います。" }
      else { reason = (error as? WebSourceFailure)?.errorDescription ?? WebSourceFailure.network.localizedDescription }
      if source.canProvideText {
        source.errorInformation = "以前に取得した本文を表示しています。" + reason
      } else {
        source.processingStatus = error is CancellationError ? .unavailable : .failed
        source.errorInformation = reason
      }
      _ = storeProjectSource(source)
      return false
    }
  }

  func cancelProjectWebFetches() {
    let ids = Set(projectWebFetchJobs.keys)
    for job in projectWebFetchJobs.values { job.task.cancel() }
    projectWebFetchJobs = [:]
    projectSourceProcessingIDs.subtract(ids)
    recoverInterruptedProjectSources()
  }
}
