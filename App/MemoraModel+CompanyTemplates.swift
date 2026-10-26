import Foundation

extension MemoraModel {
  func registerCompanyTemplate(_ url: URL) async throws {
    guard let format = CompanyTemplate.Format(rawValue: url.pathExtension.lowercased()),
          !isRestoring, isStoreWritable(), companyTemplates.count < 100 else { throw CompanyTemplateEngine.Failure.unsupported }
    let workspace = currentTeamID
    let receipt = try await ProjectSourceFiles.shared.copy(url)
    do {
      guard let storedURL = ProjectSourceFiles.resolve(receipt.reference) else { throw CompanyTemplateEngine.Failure.unsupported }
      let analysis = try await Task.detached(priority: .userInitiated) {
        try CompanyTemplateEngine.analyze(Data(contentsOf: storedURL), format: format)
      }.value
      guard !Task.isCancelled, workspace == currentTeamID, !isRestoring else { throw CancellationError() }
      let template = CompanyTemplate(name: url.deletingPathExtension().lastPathComponent, format: format,
        fileReference: receipt.reference, workspaceID: workspace, analysis: analysis)
      var candidate = companyTemplates; candidate.insert(template, at: 0)
      guard persistNow(candidate, forKey: "memora.companyTemplates.v1") else { throw CompanyTemplateEngine.Failure.unsupported }
      companyTemplates = candidate
    } catch { await ProjectSourceFiles.shared.remove([receipt.reference]); throw error }
  }

  func generateCompanyDocument(templateID: UUID, title: String, values: [String: String]) async throws -> URL {
    guard let template = companyTemplates.first(where: { $0.id == templateID && $0.workspaceID == currentTeamID }),
          template.analysis.isAvailable, let url = ProjectSourceFiles.resolve(template.fileReference), !isRestoring else { throw CompanyTemplateEngine.Failure.unsupported }
    let workspace = currentTeamID
    let data = try await Task.detached(priority: .userInitiated) {
      try CompanyTemplateEngine.fill(Data(contentsOf: url), format: template.format, values: values)
    }.value
    guard workspace == currentTeamID, companyTemplates.contains(template), !Task.isCancelled, isStoreWritable() else { throw CancellationError() }
    let name = try await ProjectSourceFiles.shared.write(data, extension: template.format.rawValue)
    var document = MemoraDocument(title: title, kind: template.format == .docx ? .document : .slides)
    document.markdown = values.sorted { $0.key < $1.key }.map { "## " + $0.key + "\n" + $0.value }.joined(separator: "\n\n")
    document.artifactFileReference = name; document.artifactFormat = template.format.rawValue.uppercased()
    document.companyTemplateID = templateID
    document.artifactRevision = document.contentRevision ?? 0
    guard !Task.isCancelled, workspace == currentTeamID, addDocument(document), let result = ProjectSourceFiles.resolve(name) else {
      await ProjectSourceFiles.shared.remove([name]); throw CancellationError()
    }
    return result
  }
}
