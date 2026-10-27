import Foundation

extension MemoraModel {
  func prepareDocumentArtifact(_ document: MemoraDocument, call: AgentToolCall) async throws -> MemoraDocument {
    let workspace = currentTeamID
    var result = document
    let templateID = UUID(uuidString: call.string("template_id"))
    let format: String
    let data: Data
    if let templateID {
      guard let template = companyTemplates.first(where: { $0.id == templateID && $0.workspaceID == workspace }),
            let url = ProjectSourceFiles.resolve(template.fileReference),
            (template.format == .docx) == (document.kind == .document) else { throw CompanyTemplateEngine.Failure.unsupported }
      let fields = call.objects("template_fields")
      let pairs = fields.compactMap { row -> (String, String)? in
        guard let name = row["name"] as? String, let value = row["value"] as? String else { return nil }
        return (name, value)
      }
      guard Set(pairs.map { $0.0 }).count == pairs.count else { throw CompanyTemplateEngine.Failure.fields }
      let values = Dictionary(uniqueKeysWithValues: pairs)
      data = try await Task.detached(priority: .userInitiated) {
        try CompanyTemplateEngine.fill(Data(contentsOf: url), format: template.format, values: values)
      }.value
      format = template.format.rawValue
      guard companyTemplates.contains(template) else { throw CancellationError() }
      result.companyTemplateID = templateID
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
    guard !Task.isCancelled, currentTeamID == workspace, !isRestoring else { throw CancellationError() }
    let name = try await ProjectSourceFiles.shared.write(data, extension: format)
    guard !Task.isCancelled, currentTeamID == workspace, !isRestoring else {
      await ProjectSourceFiles.shared.remove([name]); throw CancellationError()
    }
    result.artifactFileReference = name; result.artifactFormat = format.uppercased()
    result.artifactRevision = result.contentRevision ?? 0
    return result
  }
}
