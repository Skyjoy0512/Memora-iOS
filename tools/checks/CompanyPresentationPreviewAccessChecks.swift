import Foundation

@main struct CompanyPresentationPreviewAccessChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("company-preview-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    setenv("MEMORA_WORKSPACE_FILES_DIRECTORY", root.appendingPathComponent("files").path, 1)
    let model = try MemoraModel(storeURL: root.appendingPathComponent("store.sqlite"))
    let bytes = PPTXWriter.data(for: .init(title: "架空の会社原本", kind: .slides, slides: [.init(title: "原本", bullets: [])]))
    let name = try await ProjectSourceFiles.shared.write(bytes, extension: "pptx")
    let template = CompanyTemplate(name: "会社書式", format: .pptx, fileReference: name, analysis: try CompanyTemplateEngine.analyze(bytes, format: .pptx))
    model.companyTemplates = [template]
    let document = MemoraDocument(title: "追加資料", kind: .slides, slides: [.init(title: "判断を共有する", bullets: [], composition: .init(layout: .b01, subtitle: "架空データ"))], companyTemplateID: template.id)
    precondition(model.addDocument(document))
    let request = try model.companyPresentationPreviewRequest(for: document)
    let before = try saved(model)
    let preview = try await model.loadCompanyPresentationPreview(request)
    precondition(preview.pages.count == 1 && model.documents == [document])
    let after = try saved(model); precondition(before == after)
    let original = try Data(contentsOf: ProjectSourceFiles.resolve(name)!); precondition(original == bytes)
    for state in 0..<8 {
      model.documents = [document]; model.companyTemplates = [template]
      model.isRestoring = false; model.isStoreProtected = false; model.currentTeamID = nil; model.aiWorkspaceGeneration = request.generation
      switch state {
      case 0: model.documents[0].title = "変更された本文"
      case 1: model.documents = []
      case 2: model.companyTemplates[0].version += 1
      case 3: model.companyTemplates = []
      case 4: model.currentTeamID = "other"; model.currentTeamID = nil; model.aiWorkspaceGeneration = UUID()
      case 5: model.isRestoring = true
      case 6: model.isStoreProtected = true
      default: model.aiWorkspaceGeneration = UUID()
      }
      precondition(!model.companyPresentationPreviewIsCurrent(request))
      var preparations = 0
      do {
        _ = try await model.loadCompanyPresentationPreview(request) { _, _ in preparations += 1; return preview }
        preconditionFailure("stale preview accepted")
      } catch CompanyPresentationPreview.Failure.stale {}
      precondition(preparations == 0, "stale request started preparation")
    }
    model.documents = [document]; model.companyTemplates = [template]
    model.isRestoring = false; model.isStoreProtected = false; model.currentTeamID = nil; model.aiWorkspaceGeneration = request.generation
    var cancelledPreparations = 0
    let cancelled = Task {
      try await model.loadCompanyPresentationPreview(request) { _, _ in cancelledPreparations += 1; return preview }
    }
    cancelled.cancel()
    do { _ = try await cancelled.value; preconditionFailure("cancel ignored") } catch is CancellationError {}
    precondition(cancelledPreparations == 0, "cancelled request started preparation")

    // Each real PPTX read/render has finished before the mutation; only the final result is withheld.
    let conditions = ["unchanged", "document edit", "document delete", "template version", "template analysis", "template delete",
      "workspace switch", "workspace A-B-A", "generation", "restoring", "protected store", "cancellation"]
    for (state, condition) in conditions.enumerated() {
      model.documents = [document]; model.companyTemplates = [template]
      model.isRestoring = false; model.isStoreProtected = false; model.currentTeamID = nil; model.aiWorkspaceGeneration = request.generation
      let gate = CompanyPresentationPreviewGate()
      let work = Task {
        try await model.loadCompanyPresentationPreview(request) { capturedDocument, source in
          do {
            let value = try await MemoraModel.prepareCompanyPresentationPreview(document: capturedDocument, source: source)
            await gate.hold()
            return value
          } catch { await gate.fail(error); throw error }
        }
      }
      try await gate.arrived()
      switch state {
      case 1: model.documents[0].slides[0].title = "待機中の編集"
      case 2: model.documents = []
      case 3: model.companyTemplates[0].version += 1
      case 4: model.companyTemplates[0].analysis.engineVersion = 0
      case 5: model.companyTemplates = []
      case 6: model.currentTeamID = "other"
      case 7: model.currentTeamID = "other"; model.currentTeamID = nil; model.aiWorkspaceGeneration = UUID()
      case 8: model.aiWorkspaceGeneration = UUID()
      case 9: model.isRestoring = true
      case 10: model.isStoreProtected = true
      case 11: work.cancel()
      default: break
      }
      let documentsAtRelease = model.documents, templatesAtRelease = model.companyTemplates
      await gate.release()
      if state == 0 {
        let delivered = try await work.value
        precondition(delivered.pages == preview.pages && delivered.originalPageCount == preview.originalPageCount)
      } else if state == 11 {
        do { _ = try await work.value; preconditionFailure("cancelled result delivered") } catch is CancellationError {}
      } else {
        do { _ = try await work.value; preconditionFailure("stale result delivered: \(condition)") }
        catch CompanyPresentationPreview.Failure.stale {}
      }
      precondition(model.documents == documentsAtRelease && model.companyTemplates == templatesAtRelease, "preview changed live state")
      let savedAfter = try saved(model), sourceAfter = try Data(contentsOf: ProjectSourceFiles.resolve(name)!)
      precondition(savedAfter == before && sourceAfter == bytes, "preview changed persisted source/document")
      print("PASS held preview result: \(condition)")
    }
    model.documents = [document]; model.companyTemplates = [template]
    model.isRestoring = false; model.isStoreProtected = false; model.currentTeamID = nil; model.aiWorkspaceGeneration = request.generation
    do {
      _ = try await model.loadCompanyPresentationPreview(request) { _, _ in throw CocoaError(.fileReadCorruptFile) }
      preconditionFailure("preparation failure replaced with success")
    } catch let error as CocoaError { precondition(error.code == .fileReadCorruptFile) }
    let url = ProjectSourceFiles.resolve(name)!
    try FileManager.default.removeItem(at: url)
    do { _ = try await model.loadCompanyPresentationPreview(request); preconditionFailure("missing file accepted") } catch {}
    try bytes.write(to: url)
    var legacy = document; legacy.slides = [.init(title: "旧資料", bullets: ["保持する本文"])]
    model.documents = [legacy]
    do { _ = try model.companyPresentationPreviewRequest(for: legacy); preconditionFailure("legacy silently replaced") } catch {}
    print("Company preview access: real source/SQLite unchanged, production factory/preparation/publication checks; 8 preflight refusals, pre-cancel without work, 12 deterministically held real-worker results, typed stale/cancel/preparation errors, missing source and legacy refusal; no UI-save/OS-termination/AI/device certification")
  }

  @MainActor static func saved(_ model: MemoraModel) throws -> Data {
    let store = LocalStore(fileURL: model.fixtureStoreURL); try store.prepare()
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("No document") }
    return data
  }
}
