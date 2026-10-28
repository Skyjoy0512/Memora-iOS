import Foundation

extension MemoraModel {
  func companyPresentationExportBlocker(for document: MemoraDocument) -> CompanyPresentationExportError? {
    guard !isRestoring, isStoreWritable(), self.document(id: document.id) == document,
          document.provenance.map({ $0.workspaceID == currentTeamID }) ?? true else { return .unavailable }
    guard let template = companyTemplates.first(where: { $0.id == document.companyTemplateID && $0.workspaceID == currentTeamID }),
          template.version > 0 else { return .templateUnavailable }
    guard document.kind == .slides, !document.slides.isEmpty, document.slides.count <= 65,
          document.slides.allSatisfy({ $0.composition != nil }), document.hasValidRevisions,
          template.format == .pptx, CompanyPresentationExporter.canAppend(template.analysis) else { return .unsupported }
    guard (document.artifactHistory?.count ?? 0) < DocumentArtifactRevision.maximumHistory else { return .historyLimit }
    return nil
  }

  func companyPresentationExportRequest(for document: MemoraDocument) throws -> CompanyPresentationExportRequest {
    if let blocker = companyPresentationExportBlocker(for: document) { throw blocker }
    let template = companyTemplates.first { $0.id == document.companyTemplateID && $0.workspaceID == currentTeamID }!
    guard let original = ProjectSourceFiles.resolve(template.fileReference),
          let attributes = try? original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw CompanyPresentationExportError.templateUnavailable }
    try verifyPreviousArtifact(document)
    return .init(document: document, template: template, workspaceID: currentTeamID, generation: aiWorkspaceGeneration)
  }

  func companyPresentationExportIsCurrent(_ request: CompanyPresentationExportRequest) -> Bool {
    currentTeamID == request.workspaceID && aiWorkspaceGeneration == request.generation &&
      request.template.id == request.document.companyTemplateID && request.template.workspaceID == request.workspaceID &&
      companyTemplates.contains(request.template) && companyPresentationExportBlocker(for: request.document) == nil
  }

  func reexportCompanyPresentation(_ request: CompanyPresentationExportRequest) async throws -> MemoraDocument {
    try await CompanyPresentationExportTransaction.run(
      isCurrent: { self.companyPresentationExportIsCurrent(request) },
      prepare: { try await self.prepareCompanyPresentationExport(request) },
      commit: { try self.commitCompanyPresentationExport($0, request: request) },
      discard: { name in await self.discardCompanyPresentationExport(name, request: request) }
    )
  }

  func prepareCompanyPresentationExport(_ request: CompanyPresentationExportRequest) async throws -> MemoraDocument {
    guard companyPresentationExportIsCurrent(request) else { throw CompanyPresentationExportError.stale }
    try verifyPreviousArtifact(request.document)
    return try await prepareDocumentArtifact(request.document, call: .init(id: request.id.uuidString, name: "create_slides", arguments: [
      "template_id": request.template.id.uuidString, "template_mode": "append", "template_fields": []
    ]))
  }

  func commitCompanyPresentationExport(_ prepared: MemoraDocument, request: CompanyPresentationExportRequest) throws -> MemoraDocument {
    try Task.checkCancellation()
    guard companyPresentationExportIsCurrent(request), let index = documents.firstIndex(where: { $0.id == request.document.id }),
          let name = prepared.artifactFileReference, !request.document.artifactFileReferences.contains(name),
          name != request.template.fileReference, prepared.artifactFormat == "PPTX" else { throw CompanyPresentationExportError.stale }
    let retained = Set(documents.flatMap(\.artifactFileReferences) + companyTemplates.map(\.fileReference) + projectSources.flatMap(\.fileReferences))
    let newFile = DocumentArtifactRevision(fileReference: name, format: .pptx, contentRevision: request.document.contentRevision ?? 0)
    guard !retained.contains(name), newFile.isValid, let url = ProjectSourceFiles.resolve(name),
          let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw CompanyPresentationExportError.stale }
    try verifyPreviousArtifact(request.document)
    var expected = request.document
    expected.artifactFileReference = name; expected.artifactFormat = "PPTX"
    expected.artifactRevision = expected.contentRevision ?? 0
    expected.companyTemplateVersion = request.template.version
    guard prepared == expected else { throw CompanyPresentationExportError.stale }
    if let old = request.document.artifactFileReference {
      var history = expected.artifactHistory ?? []
      history.insert(.init(fileReference: old, format: .pptx, contentRevision: request.document.artifactRevision ?? 0,
        companyTemplateID: request.document.companyTemplateID, companyTemplateVersion: request.document.companyTemplateVersion), at: 0)
      expected.artifactHistory = history
    }
    expected.updatedAt = .now
    guard expected.hasValidRevisions else { throw CompanyPresentationExportError.unsupported }
    var candidate = documents; candidate[index] = expected
    guard persistBatch({ [(key: StorageKey.documents, data: try RecordStore.encoded(candidate))] }) else { throw CompanyPresentationExportError.save }
    documents = candidate
    invalidateProjectEvidence([.document(expected.id)])
    return expected
  }

  func discardCompanyPresentationExport(_ name: String, request: CompanyPresentationExportRequest) async {
    let retained = Set(documents.flatMap(\.artifactFileReferences) + companyTemplates.map(\.fileReference) + projectSources.flatMap(\.fileReferences)
      + request.document.artifactFileReferences + [request.template.fileReference])
    guard !retained.contains(name) else { return }
    await ProjectSourceFiles.shared.remove([name])
  }

  private func verifyPreviousArtifact(_ document: MemoraDocument) throws {
    for name in document.artifactFileReferences {
      guard let url = ProjectSourceFiles.resolve(name),
            let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw CompanyPresentationExportError.missingPrevious }
    }
    guard document.artifactFileReference == nil || document.artifactFormat?.uppercased() == "PPTX" else {
      throw CompanyPresentationExportError.unsupported
    }
  }
}
