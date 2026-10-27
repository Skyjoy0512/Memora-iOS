import Foundation

extension MemoraModel {
  func prepareDocumentArtifact(_ document: MemoraDocument, call: AgentToolCall) async throws -> MemoraDocument {
    let workspace = currentTeamID
    let generation = aiWorkspaceGeneration
    guard !isRestoring, isStoreWritable() else { throw CancellationError() }
    guard document.hasValidRevisions else { throw CompanyTemplateEngine.Failure.unsupported }
    var result = document
    let rawID = call.string("template_id"), rawMode = call.string("template_mode")
    let templateID = UUID(uuidString: rawID)
    guard (rawID.isEmpty || templateID != nil), ["", "markers", "append"].contains(rawMode),
          (rawMode.isEmpty || templateID != nil),
          (document.companyTemplateID == nil || templateID != nil) else { throw CompanyTemplateEngine.Failure.unsupported }
    var expectedTemplate: CompanyTemplate?
    let format: String
    let data: Data
    if let templateID {
      guard let template = companyTemplates.first(where: { $0.id == templateID && $0.workspaceID == workspace }),
            template.version > 0, let url = ProjectSourceFiles.resolve(template.fileReference),
            (template.format == .docx) == (document.kind == .document) else { throw CompanyTemplateEngine.Failure.unsupported }
      let fields = call.objects("template_fields")
      let pairs = fields.compactMap { row -> (String, String)? in
        guard let name = row["name"] as? String, let value = row["value"] as? String else { return nil }
        return (name, value)
      }
      guard Set(pairs.map { $0.0 }).count == pairs.count else { throw CompanyTemplateEngine.Failure.fields }
      let values = Dictionary(uniqueKeysWithValues: pairs)
      if rawMode == "append" {
        guard document.kind == .slides, template.format == .pptx,
              call.arguments["template_fields"] == nil || (call.arguments["template_fields"] as? [Any])?.isEmpty == true else { throw CompanyTemplateEngine.Failure.fields }
      }
      let worker = Task.detached(priority: .userInitiated) {
        if rawMode == "append" { return try CompanyPresentationExporter.data(for: document, template: url) }
        return try CompanyTemplateEngine.fill(url, format: template.format, values: values)
      }
      data = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      format = template.format.rawValue
      guard companyTemplates.contains(template) else { throw CancellationError() }
      result.companyTemplateID = templateID
      result.companyTemplateVersion = template.version
      expectedTemplate = template
    } else if document.kind == .document {
      data = try DOCXWriter.data(for: document); format = "docx"
    } else {
      guard document.slides.count <= 65, document.slides.allSatisfy({ slide in
        slide.composition != nil || (slide.title.count <= 80 && slide.bullets.count <= 6 && slide.bullets.allSatisfy { $0.count <= 80 })
      }) else { throw CompanyTemplateEngine.Failure.tooLong }
      data = try await Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        try PresentationExportCheck.validate(document)
        return PPTXWriter.data(for: document)
      }.value
      format = "pptx"
    }
    var validation = try OfficeArchiveReader(data: data)
    _ = try OfficeDocumentExtraction.read(archive: &validation, extension: format)
    guard !Task.isCancelled, currentTeamID == workspace, generation == aiWorkspaceGeneration, !isRestoring, isStoreWritable(),
          expectedTemplate.map({ companyTemplates.contains($0) }) ?? true else { throw CancellationError() }
    let name = try await ProjectSourceFiles.shared.write(data, extension: format)
    guard !Task.isCancelled, currentTeamID == workspace, generation == aiWorkspaceGeneration, !isRestoring, isStoreWritable(),
          expectedTemplate.map({ companyTemplates.contains($0) }) ?? true else {
      await ProjectSourceFiles.shared.remove([name]); throw CancellationError()
    }
    result.artifactFileReference = name; result.artifactFormat = format.uppercased()
    result.artifactRevision = result.contentRevision ?? 0
    return result
  }
}
