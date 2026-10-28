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
      do { _ = try await model.loadCompanyPresentationPreview(request); preconditionFailure("stale preview accepted") } catch {}
    }
    model.documents = [document]; model.companyTemplates = [template]
    model.isRestoring = false; model.isStoreProtected = false; model.currentTeamID = nil; model.aiWorkspaceGeneration = request.generation
    let cancelled = Task { try await model.loadCompanyPresentationPreview(request) }
    cancelled.cancel()
    do { _ = try await cancelled.value; preconditionFailure("cancel ignored") } catch {}
    let url = ProjectSourceFiles.resolve(name)!
    try FileManager.default.removeItem(at: url)
    do { _ = try await model.loadCompanyPresentationPreview(request); preconditionFailure("missing file accepted") } catch {}
    try bytes.write(to: url)
    var legacy = document; legacy.slides = [.init(title: "旧資料", bullets: ["保持する本文"])]
    model.documents = [legacy]
    do { _ = try model.companyPresentationPreviewRequest(for: legacy); preconditionFailure("legacy silently replaced") } catch {}
    print("Company preview access: real source/SQLite unchanged, production snapshot/factory/worker checks, edited/deleted document, template update/delete, workspace A-B-A, restore/protection/generation, cancel, missing source, legacy refusal; no UI-save/AI/device certification")
  }

  @MainActor static func saved(_ model: MemoraModel) throws -> Data {
    let store = LocalStore(fileURL: model.fixtureStoreURL); try store.prepare()
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("No document") }
    return data
  }
}
