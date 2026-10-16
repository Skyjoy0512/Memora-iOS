import Foundation

extension MemoraModel {
  func saveResearchDocument(_ id: UUID) async throws -> UUID {
    guard let report = webResearch(id: id), report.workspaceID == currentTeamID,
          !report.answer.isEmpty, !webResearchBusyIDs.contains(id) else { throw CompanyTemplateEngine.Failure.fields }
    let links = report.sources.map { "- [\($0.title)](\($0.url.absoluteString))（\($0.kind.label)）" }.joined(separator: "\n")
    let unfinished = report.status == .complete ? "" : "調査は未完了です。\(report.error ?? "")\n\n"
    var document = MemoraDocument(title: String(report.query.prefix(120)), kind: .document,
      markdown: unfinished + report.answer + "\n\n## 取得した根拠\n" + links)
    document = try await prepareDocumentArtifact(document, call: AgentToolCall(id: UUID().uuidString, name: "create_document", arguments: [:]))
    guard webResearch(id: id) == report, !Task.isCancelled, addDocument(document) else {
      if let file = document.artifactFileReference { await ProjectSourceFiles.shared.remove([file]) }
      throw CancellationError()
    }
    return document.id
  }
}
