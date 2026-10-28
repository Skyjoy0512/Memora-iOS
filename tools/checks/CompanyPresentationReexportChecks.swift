import Foundation
import SQLite3

@main struct CompanyPresentationReexportChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("company-reexport-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    setenv("MEMORA_WORKSPACE_FILES_DIRECTORY", root.appendingPathComponent("files").path, 1)
    try await happyPath(root)
    for mutation in Mutation.allCases { try await interrupted(root, mutation: mutation) }
    try await rejectionAndCodec(root)
    print("Company reexport passed: real Swift PPTX/SQLite, retained history/old bytes/template versions, fresh current-document commit, unrelated edits preserved, suspended prepare races, cancellation, SQL rollback/file cleanup, shared-file deletion protection, legacy/invalid history; no network/AI/device or Office certification")
  }

  @MainActor static func fixture(_ root: URL) async throws -> (MemoraModel, MemoraDocument) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("\(UUID()).sqlite"))
    let bytes = PPTXWriter.data(for: .init(title: "会社原本", kind: .slides, slides: [.init(title: "原本のページ", bullets: ["保持する元データ"]) ]))
    let name = try await ProjectSourceFiles.shared.write(bytes, extension: "pptx")
    var template = CompanyTemplate(name: "架空の会社書式", format: .pptx, fileReference: name,
      analysis: try CompanyTemplateEngine.analyze(bytes, format: .pptx))
    template.version = 3; model.companyTemplates = [template]
    var document = MemoraDocument(title: "会社資料", kind: .slides,
      slides: [.init(title: "判断を共有する", bullets: [], notes: "保持するノート", composition: .init(layout: .b01, subtitle: "架空データ"))])
    document = try await model.prepareDocumentArtifact(document, call: .init(id: "initial", name: "create_slides", arguments: [
      "template_id": template.id.uuidString, "template_mode": "append"]))
    precondition(model.addDocument(document))
    var edited = document.slides; edited[0].title = "編集後の判断を共有する"
    precondition(model.updateDocumentSlides(document.id, title: document.title, slides: edited, expectedUpdatedAt: document.updatedAt))
    return (model, model.document(id: document.id)!)
  }

  @MainActor static func happyPath(_ root: URL) async throws {
    let (model, edited) = try await fixture(root)
    let originalName = model.companyTemplates[0].fileReference
    let oldName = edited.artifactFileReference!
    let original = try Data(contentsOf: ProjectSourceFiles.resolve(originalName)!)
    let oldBytes = try Data(contentsOf: ProjectSourceFiles.resolve(oldName)!)
    let request = try model.companyPresentationExportRequest(for: edited)
    let unrelated = MemoraDocument(title: "別の資料", kind: .document, markdown: "同時編集を保持")
    precondition(model.addDocument(unrelated))
    let result = try await model.reexportCompanyPresentation(request)
    precondition(result.id == edited.id && result.slides == edited.slides && !result.hasOutdatedArtifact)
    precondition(result.contentRevision == edited.contentRevision && result.artifactHistory?.first?.fileReference == oldName)
    precondition(result.artifactHistory?.first?.contentRevision == 0 && result.artifactHistory?.first?.companyTemplateVersion == 3)
    precondition(model.document(id: unrelated.id) == unrelated)
    let reloaded = try stored(model)
    precondition(reloaded == model.documents)
    let currentBytes = try Data(contentsOf: ProjectSourceFiles.resolve(result.artifactFileReference!)!)
    var analyzer = try CompanyPresentationAnalyzer(data: currentBytes)
    let profile = try analyzer.measure(); precondition(profile.slideCount == 2)
    let preservedOriginal = try Data(contentsOf: ProjectSourceFiles.resolve(originalName)!)
    let preservedOld = try Data(contentsOf: ProjectSourceFiles.resolve(oldName)!)
    precondition(preservedOriginal == original && preservedOld == oldBytes)
    precondition(!model.companyPresentationExportIsCurrent(request))

    model.companyTemplates[0].version = 4
    let nextRequest = try model.companyPresentationExportRequest(for: result)
    precondition(nextRequest.template.version == 4 && nextRequest.document.companyTemplateVersion == 3)
    let next = try await model.reexportCompanyPresentation(nextRequest)
    precondition(next.companyTemplateVersion == 4 && next.artifactHistory?.count == 2)
    precondition(next.artifactHistory?[0].fileReference == result.artifactFileReference && next.artifactHistory?[0].companyTemplateVersion == 3)
    let sharedDocument = MemoraDocument(title: "同じ成果物の参照", kind: .slides, artifactFileReference: oldName, artifactFormat: "PPTX")
    precondition(model.addDocument(sharedDocument))
    model.projectSources = [.init(kind: .document, title: "別のソース", localFileReference: result.artifactFileReference)]
    model.deleteDocument(next.id)
    for _ in 0..<100 where FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(next.artifactFileReference!)!.path) {
      try await Task.sleep(for: .milliseconds(10))
    }
    precondition(!FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(next.artifactFileReference!)!.path))
    for name in [oldName, originalName, result.artifactFileReference!] {
      precondition(FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(name)!.path))
    }
    print("PASS reexport: edit → confirmation snapshot → real export → atomic save → SQLite reopen → template v4 → retained history → shared-file-safe delete")
  }

  enum Mutation: String, CaseIterable {
    case edit, delete, workspaceRoundTrip, generation, templateVersion, templateAnalysis, protectedStore, restoring, cancel, sqlFailure, adoptedFile
  }

  @MainActor static func interrupted(_ root: URL, mutation: Mutation) async throws {
    let (model, document) = try await fixture(root)
    var mismatched = try model.companyPresentationExportRequest(for: document)
    var otherTemplate = model.companyTemplates[0]; otherTemplate.id = UUID()
    model.companyTemplates.append(otherTemplate); mismatched.template = otherTemplate
    precondition(!model.companyPresentationExportIsCurrent(mismatched))
    let request = try model.companyPresentationExportRequest(for: document)
    let gate = PreparedGate()
    var preparedName: String?
    let work = Task {
      try await CompanyPresentationExportTransaction.run(
        isCurrent: { model.companyPresentationExportIsCurrent(request) },
        prepare: {
          do {
            let value = try await model.prepareCompanyPresentationExport(request)
            preparedName = value.artifactFileReference
            await gate.hold()
            return value
          } catch { gate.fail(error); throw error }
        },
        commit: { try model.commitCompanyPresentationExport($0, request: request) },
        discard: { await model.discardCompanyPresentationExport($0, request: request) }
      )
    }
    try await gate.arrived()
    var database: OpaquePointer?
    defer { if let database { sqlite3_close(database) } }
    switch mutation {
    case .edit:
      var slides = document.slides; slides[0].title = "後から保存した編集"
      precondition(model.updateDocumentSlides(document.id, title: document.title, slides: slides, expectedUpdatedAt: document.updatedAt))
    case .delete: model.deleteDocument(document.id)
    case .workspaceRoundTrip:
      model.currentTeamID = "other"; model.aiWorkspaceGeneration = UUID()
      model.currentTeamID = nil; model.aiWorkspaceGeneration = UUID()
    case .generation: model.aiWorkspaceGeneration = UUID()
    case .templateVersion: model.companyTemplates[0].version += 1
    case .templateAnalysis: model.companyTemplates[0].analysis.engineVersion = 0
    case .protectedStore: model.isStoreProtected = true
    case .restoring: model.isRestoring = true
    case .cancel: work.cancel()
    case .sqlFailure:
      precondition(sqlite3_open(model.fixtureStoreURL.path, &database) == SQLITE_OK)
      precondition(sqlite3_exec(database, "CREATE TRIGGER reject_export BEFORE INSERT ON documents WHEN NEW.key = 'documents' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    case .adoptedFile: model.companyTemplates[0].fileReference = preparedName!
    }
    let expected = model.documents
    let expectedStored = try stored(model)
    gate.release()
    do { _ = try await work.value; preconditionFailure("stale/cancelled/failed output published: \(mutation)") } catch {}
    precondition(model.documents == expected)
    let afterStored = try stored(model); precondition(afterStored == expectedStored)
    let exists = FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(preparedName!)!.path)
    precondition(exists == (mutation == .adoptedFile), "incorrect prepared-file cleanup")
    print("PASS reexport suspended race: \(mutation.rawValue), no stale publication or lost edit")
  }

  @MainActor static func rejectionAndCodec(_ root: URL) async throws {
    let (model, document) = try await fixture(root)
    let bytes = try JSONEncoder().encode(document)
    var json = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    json.removeValue(forKey: "artifactHistory")
    let legacy = try JSONDecoder().decode(MemoraDocument.self, from: JSONSerialization.data(withJSONObject: json))
    precondition(legacy.artifactHistory == nil && legacy.hasValidRevisions)
    let valid = DocumentArtifactRevision(fileReference: "older.pptx", format: .pptx, contentRevision: 0)
    for bad in [
      DocumentArtifactRevision(fileReference: "../unsafe.pptx", format: .pptx, contentRevision: 0),
      DocumentArtifactRevision(fileReference: "bad.docx", format: .pptx, contentRevision: 0),
      DocumentArtifactRevision(fileReference: "older.pptx", format: .pptx, contentRevision: -1),
      DocumentArtifactRevision(fileReference: "older.pptx", format: .pptx, contentRevision: 2),
      DocumentArtifactRevision(fileReference: document.artifactFileReference!, format: .pptx, contentRevision: 0),
      DocumentArtifactRevision(fileReference: "older.pptx", format: .pptx, contentRevision: 0, companyTemplateVersion: 1)
    ] {
      var invalid = document; invalid.artifactHistory = [bad]; precondition(!invalid.hasValidRevisions)
      precondition(!model.addDocument(invalid))
    }
    var duplicate = document; duplicate.artifactHistory = [valid, valid]; precondition(!duplicate.hasValidRevisions)
    var full = document
    full.artifactHistory = (0..<100).map { .init(fileReference: "history-\($0).pptx", format: .pptx, contentRevision: 0) }
    model.documents = [full]
    precondition(model.companyPresentationExportBlocker(for: full) != nil)
    model.documents = [document]
    let url = ProjectSourceFiles.resolve(document.artifactFileReference!)!, original = try Data(contentsOf: url)
    try FileManager.default.removeItem(at: url)
    do { _ = try model.companyPresentationExportRequest(for: document); preconditionFailure("missing old file treated as retained") } catch {}
    try original.write(to: url)
    let templateURL = ProjectSourceFiles.resolve(model.companyTemplates[0].fileReference)!
    let templateBytes = try Data(contentsOf: templateURL)
    try FileManager.default.removeItem(at: templateURL)
    do { _ = try model.companyPresentationExportRequest(for: document); preconditionFailure("missing template file allowed confirmation") } catch {}
    try templateBytes.write(to: templateURL)
    model.companyTemplates = []
    do { _ = try model.companyPresentationExportRequest(for: document); preconditionFailure("missing template fell back to standard theme") } catch {}
    print("PASS reexport refusal: missing original/template, history capacity, invalid/duplicate/path/format/revision metadata, old codec")
  }

  @MainActor static func stored(_ model: MemoraModel) throws -> [MemoraDocument] {
    let store = LocalStore(fileURL: model.fixtureStoreURL); try store.prepare()
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.documents) else { return [] }
    return try JSONDecoder().decode([MemoraDocument].self, from: data)
  }
}

@MainActor private final class PreparedGate {
  private var ready = false
  private var arrival: CheckedContinuation<Void, Error>?
  private var failure: Error?
  private var held: CheckedContinuation<Void, Never>?
  func hold() async {
    ready = true; arrival?.resume(); arrival = nil
    await withCheckedContinuation { held = $0 }
  }
  func arrived() async throws {
    if let failure { throw failure }
    if !ready { try await withCheckedThrowingContinuation { arrival = $0 } }
  }
  func fail(_ error: Error) { failure = error; ready = true; arrival?.resume(throwing: error); arrival = nil }
  func release() { held?.resume(); held = nil }
}
