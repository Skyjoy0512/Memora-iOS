import Foundation

extension MemoraModel {
  /// Existing templates keep their file and ID; reanalysis is an explicit, local operation.
  func refreshCompanyTemplateAnalysis(_ id: UUID) async throws {
    guard !isRestoring, isStoreWritable(),
          let original = companyTemplates.first(where: { $0.id == id && $0.workspaceID == currentTeamID }),
          let url = ProjectSourceFiles.resolve(original.fileReference) else { throw CompanyTemplateEngine.Failure.unsupported }
    let workspace = currentTeamID
    let generation = aiWorkspaceGeneration
    let worker = Task.detached(priority: .userInitiated) {
      try CompanyTemplateEngine.analyze(url, format: original.format)
    }
    let analysis = try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: { worker.cancel() }
    try finishCompanyTemplateAnalysis(analysis, original: original, workspace: workspace, generation: generation)
  }

  func finishCompanyTemplateAnalysis(_ analysis: CompanyTemplateEngine.Analysis, original: CompanyTemplate,
                                     workspace: String?, generation: UUID) throws {
    guard !Task.isCancelled, !isRestoring, workspace == currentTeamID,
          original.workspaceID == workspace, generation == aiWorkspaceGeneration, isStoreWritable(),
          let index = companyTemplates.firstIndex(of: original) else { throw CancellationError() }
    var candidate = companyTemplates
    candidate[index].analysis = analysis
    candidate[index].updatedAt = .now
    guard persistNow(candidate, forKey: "memora.companyTemplates.v1") else { throw CompanyTemplateEngine.Failure.save }
    companyTemplates = candidate
  }
}
