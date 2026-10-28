import Foundation

extension MemoraModel {
  func companyPresentationPreviewRequest(for document: MemoraDocument) throws -> CompanyPresentationPreviewRequest {
    guard document.kind == .slides, document.hasValidRevisions, (1...65).contains(document.slides.count),
          Set(document.slides.map(\.id)).count == document.slides.count,
          document.slides.allSatisfy({ $0.composition != nil }),
          let template = companyTemplates.first(where: { $0.id == document.companyTemplateID && $0.workspaceID == currentTeamID }),
          template.format == .pptx, template.version > 0 else { throw CompanyPresentationPreview.Failure.unsupported }
    let request = CompanyPresentationPreviewRequest(document: document, template: template, workspaceID: currentTeamID, generation: aiWorkspaceGeneration)
    guard companyPresentationPreviewIsCurrent(request) else { throw CompanyPresentationPreview.Failure.stale }
    return request
  }

  func companyPresentationPreviewIsCurrent(_ request: CompanyPresentationPreviewRequest) -> Bool {
    !isRestoring && !isStoreProtected && currentTeamID == request.workspaceID && aiWorkspaceGeneration == request.generation &&
      document(id: request.document.id) == request.document && companyTemplates.contains(request.template) &&
      request.template.id == request.document.companyTemplateID && request.template.workspaceID == currentTeamID &&
      (request.document.provenance.map { $0.workspaceID == currentTeamID } ?? true)
  }

  func loadCompanyPresentationPreview(_ request: CompanyPresentationPreviewRequest) async throws -> CompanyPresentationPreview {
    guard companyPresentationPreviewIsCurrent(request), let source = ProjectSourceFiles.resolve(request.template.fileReference) else { throw CompanyPresentationPreview.Failure.stale }
    let document = request.document
    let worker = Task.detached(priority: .userInitiated) {
      let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw CompanyPresentationPreview.Failure.unsupported }
      let reader = try FileHandle(forReadingFrom: source); defer { try? reader.close() }
      let data = try reader.read(upToCount: OfficeArchiveReader.maximumArchiveBytes + 1) ?? Data()
      return try CompanyPresentationPreview.make(document: document, template: data)
    }
    let preview = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard companyPresentationPreviewIsCurrent(request) else { throw CompanyPresentationPreview.Failure.stale }
    return preview
  }
}
