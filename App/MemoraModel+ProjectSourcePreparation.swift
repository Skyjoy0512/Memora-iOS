import Foundation

extension MemoraModel {
  func prepareProjectLocalSource(_ id: UUID,
    extract: (URL) async throws -> ProjectSourceExtractionResult
  ) async {
    guard var context = ProjectSourcePreparationContext(id, in: self),
          context.source.processingStatus != .ready,
          !projectSourceProcessingIDs.contains(id), let name = context.source.localFileReference,
          let file = ProjectSourceFiles.resolve(name) else { return }
    projectSourceProcessingIDs.insert(id)
    defer {
      projectSourceProcessingIDs.remove(id)
      recoverInterruptedProjectSources()
    }
    context.source.processingStatus = .processing
    guard storeProjectSource(context.source) else { return }
    var created: [String] = []
    do {
      let result = try await extract(file)
      try Task.checkCancellation()
      guard context.isCurrent(in: self) else { return }
      if context.source.kind == .pdf, context.source.extractedTextReference != nil, result.blocks.isEmpty {
        var previous = context.source
        previous.processingStatus = .ready
        if let page = result.resumePage { previous.resumePage = page }
        if !result.ocrFailedPages.isEmpty { previous.ocrFailedPages = result.ocrFailedPages }
        previous.errorInformation = "以前に読み取った本文を表示しています。" +
          (result.notice ?? "新しい本文を読み取れませんでした。元のPDFを確認して再試行してください。")
        previous.updatedAt = .now
        _ = storeProjectSource(previous)
        return
      }
      let bytes = try JSONEncoder().encode(result.blocks)
      guard bytes.count <= ProjectSourceTextReader.maximumBytes else {
        throw ProjectSourceFiles.Failure.extractedTextTooLarge
      }
      var text: String?
      if !result.blocks.isEmpty {
        text = try await ProjectSourceFiles.shared.write(bytes, extension: "json")
        if let text { created.append(text) }
      }
      guard context.isCurrent(in: self) else {
        await ProjectSourceFiles.shared.remove(created); return
      }
      var thumb: String?
      if let data = result.thumbnail {
        thumb = try await ProjectSourceFiles.shared.write(data, extension: "jpg")
        if let thumb { created.append(thumb) }
      }
      guard context.isCurrent(in: self) else {
        await ProjectSourceFiles.shared.remove(created); return
      }
      var current = context.source
      current.retainRevision()
      current.extractedTextReference = text
      current.thumbnailReference = thumb
      current.processingStatus = text == nil ? .unavailable : .ready
      current.textCoverage = text == nil ? nil : result.coverage
      current.acquiredAt = .now
      current.pageCount = result.pageCount
      current.unreadablePages = result.unreadablePages
      current.omittedPages = result.omittedPages
      current.ocrPages = result.ocrPages
      current.ocrFailedPages = result.ocrFailedPages
      current.resumePage = result.resumePage
      current.updatedAt = .now
      current.errorInformation = result.notice
      guard storeProjectSource(current) else {
        await ProjectSourceFiles.shared.remove(created); return
      }
      let retained = Set(projectSources.flatMap(\.fileReferences))
      await ProjectSourceFiles.shared.remove(context.source.fileReferences.filter { !retained.contains($0) })
    } catch {
      await ProjectSourceFiles.shared.remove(created)
      guard context.isCurrent(in: self, allowsCancellation: true) else { return }
      var current = context.source
      let hasPreviousPDFText = current.kind == .pdf && current.extractedTextReference != nil
      current.processingStatus = hasPreviousPDFText ? .ready : .failed
      let reason = error is CancellationError
        ? "解析を停止しました。元ファイルは保存されています。"
        : (error as? LocalizedError)?.errorDescription ?? "解析できませんでした。元ファイルは保存されています。"
      current.errorInformation = (hasPreviousPDFText ? "以前に読み取った本文を表示しています。" : "") + reason
      _ = storeProjectSource(current)
    }
  }
}
