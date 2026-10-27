import Foundation
import SQLite3

@main struct CompanyTemplateAnalysisChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let file = root.appendingPathComponent("split-template.docx")
    let originalFile = try Data(contentsOf: file)
    ProjectSourceFiles.root = root
    let url = root.appendingPathComponent("template-analysis.sqlite")
    let store = LocalStore(fileURL: url); try store.prepare()
    let model = MemoraModel(store: store)
    let old = CompanyTemplate(name: "架空の会社書式", format: .docx, fileReference: file.lastPathComponent,
      analysis: .init(placeholders: ["body"], features: [], unsupportedSplitMarkers: true))
    let foreign = CompanyTemplate(name: "別の範囲", format: .docx, fileReference: file.lastPathComponent, workspaceID: "team", analysis: old.analysis)
    let seed = [old, foreign]
    model.companyTemplates = seed
    try await model.refreshCompanyTemplateAnalysis(old.id)
    let refreshed = model.companyTemplates[0]
    precondition(refreshed.analysis.engineVersion == CompanyTemplateEngine.analysisVersion && refreshed.analysis.isAvailable)
    precondition(refreshed.analysis.placeholders == ["body", "title"] && refreshed.version == old.version)
    precondition(refreshed.id == old.id && refreshed.fileReference == old.fileReference && model.companyTemplates[1] == foreign)
    let actualFile = try Data(contentsOf: file)
    precondition(actualFile == originalFile)
    let reopened = LocalStore(fileURL: url); try reopened.prepare()
    guard case .data(let saved) = reopened.readOutcome("memora.companyTemplates.v1") else { preconditionFailure("no analysis document") }
    let decoded = try JSONDecoder().decode([CompanyTemplate].self, from: saved)
    precondition(decoded == model.companyTemplates)
    let generation = model.aiWorkspaceGeneration
    let analysis = refreshed.analysis
    func denied(_ mutation: () -> Void) {
      model.companyTemplates = seed; model.currentTeamID = nil
      model.isRestoring = false; model.isStoreProtected = false; model.aiWorkspaceGeneration = generation
      mutation()
      let unchanged = model.companyTemplates
      do {
        try model.finishCompanyTemplateAnalysis(analysis, original: old, workspace: nil, generation: generation)
        preconditionFailure("stale analysis published")
      } catch {}
      precondition(model.companyTemplates == unchanged)
    }
    denied { model.currentTeamID = "team" }
    denied { model.aiWorkspaceGeneration = UUID() } // Includes personal -> team -> personal.
    denied { model.isRestoring = true }
    denied { model.isStoreProtected = true }
    denied { model.companyTemplates.removeFirst() }
    denied { model.companyTemplates[0].fileReference = "replaced.docx" }
    denied { model.companyTemplates[0].allowedUsers = [] }
    model.aiWorkspaceGeneration = generation; model.companyTemplates = seed
    let cancelled = Task { @MainActor in
      try model.finishCompanyTemplateAnalysis(analysis, original: old, workspace: nil, generation: generation)
    }
    cancelled.cancel()
    do { try await cancelled.value; preconditionFailure("cancelled analysis applied") } catch {}
    precondition(model.companyTemplates == seed)
    precondition(model.persistNow(seed, forKey: "memora.companyTemplates.v1"))
    guard case .data(let beforeFailure) = store.readOutcome("memora.companyTemplates.v1") else { preconditionFailure("missing failure baseline") }
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_analysis BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    do { try model.finishCompanyTemplateAnalysis(analysis, original: old, workspace: nil, generation: generation); preconditionFailure("failed save published") } catch {}
    precondition(model.companyTemplates == seed)
    guard case .data(let afterFailure) = store.readOutcome("memora.companyTemplates.v1") else { preconditionFailure("lost old data") }
    precondition(afterFailure == beforeFailure)
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_analysis", nil, nil, nil) == SQLITE_OK)
    try model.finishCompanyTemplateAnalysis(analysis, original: old, workspace: nil, generation: generation)
    precondition(model.companyTemplates[0].analysis == analysis)
    let powerpoint = CompanyTemplate(name: "架空の企業PPTX", format: .pptx, fileReference: "measured-template.pptx", analysis: old.analysis)
    model.companyTemplates.append(powerpoint)
    try await model.refreshCompanyTemplateAnalysis(powerpoint.id)
    precondition(model.companyTemplates.last?.analysis.presentation?.layouts.first?.placeholders.first?.frameSource == "ppt/slideMasters/slideMaster1.xml")
    guard case .data(let savedProfile) = reopened.readOutcome("memora.companyTemplates.v1") else { preconditionFailure("missing profile") }
    let reloadedProfile = try JSONDecoder().decode([CompanyTemplate].self, from: savedProfile)
    precondition(reloadedProfile == model.companyTemplates && reloadedProfile.last?.analysis.presentation?.isValid == true)
    print("CompanyTemplateAnalysisChecks: passed (production explicit local refresh, old metadata upgrade, unchanged file/ID/version, real SQLite reopen/failure, stale/edit/delete/workspace/generation/protection/restore/cancel; stored state and file resolver are fixtures)")
  }
}

@MainActor final class MemoraModel {
  var store: LocalStore
  var companyTemplates: [CompanyTemplate] = []
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var isRestoring = false
  var isStoreProtected = false
  init(store: LocalStore) { self.store = store }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do { try store.write(key, data: JSONEncoder().encode(value)); return true } catch { return false }
  }
}

@MainActor enum ProjectSourceFiles {
  static var root = URL(fileURLWithPath: "/unused-template-fixtures")
  static func resolve(_ name: String) -> URL? { ["split-template.docx", "measured-template.pptx"].contains(name) ? root.appendingPathComponent(name) : nil }
}
