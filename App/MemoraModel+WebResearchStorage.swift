import Foundation

extension MemoraModel {
  func webResearch(id: UUID) -> WebResearchReport? { webResearchReports.first { $0.id == id } }

  @discardableResult
  func storeWebResearch(_ report: WebResearchReport) -> Bool {
    guard !isRestoring, report.workspaceID == currentTeamID else { return false }
    var candidate = webResearchReports
    if let index = candidate.firstIndex(where: { $0.id == report.id }) { candidate[index] = report }
    else { candidate.insert(report, at: 0) }
    guard persistNow(candidate, forKey: "memora.webResearch.v1") else { return false }
    webResearchReports = candidate
    return true
  }

  func saveWebResearch(_ id: UUID, to projectID: UUID) async throws -> Bool {
    guard !Task.isCancelled, !isRestoring, isStoreWritable(), currentTeamID == nil,
          space(id: projectID) != nil, var report = webResearch(id: id), report.workspaceID == currentTeamID,
          !webResearchBusyIDs.contains(id), !report.sources.isEmpty, report.savedProjectID == nil else { return false }
    let workspaceID = currentTeamID
    let originalReport = report
    let snapshot = projectSources
    var candidateSources = snapshot
    var created: [String] = []
    do {
      for evidence in report.sources {
        if let index = candidateSources.firstIndex(where: { $0.projectID == projectID && $0.originalURL == evidence.url }) {
          if candidateSources[index].extractedTextReference == nil {
            let name = try await ProjectSourceFiles.shared.write(JSONEncoder().encode([ProjectSourceText(text: evidence.text)]), extension: "json")
            created.append(name)
            candidateSources[index].extractedTextReference = name
            candidateSources[index].processingStatus = .ready
            candidateSources[index].textCoverage = .partial
            candidateSources[index].errorInformation = "\(evidence.kind.label)を保存しました。ページ全体のコピーではありません。"
          }
          report.savedSourceIDs.append(candidateSources[index].id); continue
        }
        let name = try await ProjectSourceFiles.shared.write(JSONEncoder().encode([ProjectSourceText(text: evidence.text)]), extension: "json")
        created.append(name)
        var source = ProjectSource(projectID: projectID, kind: .web, title: evidence.title, originalURL: evidence.url,
          extractedTextReference: name, processingStatus: .ready)
        source.textCoverage = .partial
        source.metadata = ["researchReportID": report.id.uuidString, "evidenceKind": evidence.kind.label,
          "retrievedAt": evidence.retrievedAt.ISO8601Format()]
        source.errorInformation = "\(evidence.kind.label)を保存しました。ページ全体のコピーではありません。"
        candidateSources.insert(source, at: 0); report.savedSourceIDs.append(source.id)
      }
      let links = report.sources.map { "- [\($0.title)](\($0.url.absoluteString))（\($0.kind.label)）" }.joined(separator: "\n")
      let state = report.status == .complete ? "" : "調査は未完了です。\(report.error ?? "")\n\n"
      let body = "# \(report.query)\n\n" + state + (report.answer.isEmpty ? "AIの要約は未生成です。取得済みソースを確認してください。" : report.answer) + "\n\n## 取得ソース\n" + links
      let name = try await ProjectSourceFiles.shared.write(JSONEncoder().encode([ProjectSourceText(text: body)]), extension: "json")
      created.append(name)
      var note = ProjectSource(projectID: projectID, kind: .note, title: "調査: \(report.query.prefix(100))",
        extractedTextReference: name, processingStatus: .ready)
      note.textCoverage = .complete
      note.metadata = ["researchReportID": report.id.uuidString]
      candidateSources.insert(note, at: 0)
      report.savedNoteID = note.id; report.savedProjectID = projectID
      guard !Task.isCancelled, currentTeamID == workspaceID, !isRestoring, isStoreWritable(),
            space(id: projectID) != nil, projectSources == snapshot, !webResearchBusyIDs.contains(id),
            webResearch(id: id) == originalReport else { await ProjectSourceFiles.shared.remove(created); return false }
      var candidateReports = webResearchReports
      guard let index = candidateReports.firstIndex(where: { $0.id == id }) else { await ProjectSourceFiles.shared.remove(created); return false }
      candidateReports[index] = report
      guard persistBatch({ [
        (key: StorageKey.projectSources, data: try RecordStore.encoded(candidateSources)),
        (key: "memora.webResearch.v1", data: try RecordStore.encoded(candidateReports))
      ] }) else { await ProjectSourceFiles.shared.remove(created); return false }
      projectSources = candidateSources; webResearchReports = candidateReports
      invalidateProjectEvidence(candidateSources.filter { $0.projectID == projectID }.map { .source($0.id) })
      noteProjectUsed(projectID)
      return true
    } catch { await ProjectSourceFiles.shared.remove(created); throw error }
  }
}
