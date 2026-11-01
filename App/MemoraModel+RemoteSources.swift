import Foundation

extension MemoraModel {
  func acquireRemoteSource(_ id: UUID, refresh: Bool = false) async {
    guard var context = ProjectSourcePreparationContext(id, in: self), (context.source.kind == .web || (refresh && context.source.kind == .pdf)),
          let url = context.source.originalURL, (refresh || !context.source.canProvideText),
          !projectSourceProcessingIDs.contains(id) else { return }
    projectSourceProcessingIDs.insert(id)
    defer { projectSourceProcessingIDs.remove(id); recoverInterruptedProjectSources() }
    let originalStatus = context.source.processingStatus
    context.source.processingStatus = .processing
    guard storeProjectSource(context.source) else { return }
    var created: String?
    do {
      let result = try await WebSourceFetcher().fetch(url)
      guard context.isCurrent(in: self) else { return }
      if let data = result.fileData {
        let name = try await ProjectSourceFiles.shared.write(data, extension: "pdf")
        created = name
        guard context.isCurrent(in: self) else { await ProjectSourceFiles.shared.remove([name]); return }
        var source = context.source
        source.retainRevision()
        source.kind = .pdf
        source.localFileReference = name
        source.acquiredAt = result.fetchedAt
        source.metadata = (source.metadata ?? [:]).merging(["webFinalURL": result.finalURL.absoluteString]) { _, new in new }
        guard storeProjectSource(source) else { await ProjectSourceFiles.shared.remove([name]); return }
        created = nil
        projectSourceProcessingIDs.remove(id)
        await prepareProjectLocalSource(id, extract: ProjectSourceExtraction.extract)
      } else {
        // Reuse the transaction/revalidation path without downloading twice.
        projectSourceProcessingIDs.remove(id)
        _ = await fetchProjectWebSource(id, prepared: result)
      }
    } catch {
      if let created { await ProjectSourceFiles.shared.remove([created]) }
      guard context.isCurrent(in: self, allowsCancellation: true) else { return }
      var source = context.source
      source.processingStatus = source.extractedTextReference == nil ? .failed : originalStatus
      source.errorInformation = error is CancellationError ? "取得が中断されました。再試行できます。" : error.localizedDescription
      _ = storeProjectSource(source)
    }
  }
}
