import Foundation

enum AIEngine { case foundation, cloud }
struct LLMSelection: Equatable { var isMemoraIntelligence = false; var model = "fixture" }
enum AIEngineService { static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine } }
@MainActor private enum RevisionAccessFixture {
  static var engine = AIEngine.cloud
  static var llm = LLMSelection()
  static var configurationRevision = UUID()
}
extension MemoraModel {
  var askAIConfiguration: (engine: AIEngine, llm: LLMSelection) { (RevisionAccessFixture.engine, RevisionAccessFixture.llm) }
  var summaryConfigurationIdentity: [UUID] { [RevisionAccessFixture.configurationRevision] }
}

@main
struct PresentationRevisionAccessChecks {
  @MainActor static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("revision-access-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try MemoraModel(storeURL: root.appendingPathComponent("store.sqlite"))
    var privacy = RecordPrivacy(classification: .general); privacy.allowsCloudAI = true
    let meeting = Meeting(title: "許可された会議", privacy: privacy)
    model.meetings = [meeting]
    let reference = model.recordReference(for: .meeting(meeting.id))!
    var document = MemoraDocument(title: "保存した資料", kind: .slides, slides: [.init(title: "主張", bullets: [])],
      sourceRecordIDs: [meeting.id], provenance: .init(records: [reference], isComplete: true))
    precondition(model.addDocument(document))
    func authorization() -> @MainActor () -> Bool {
      model.presentationRevisionAuthorization(for: document, engine: .cloud, llm: RevisionAccessFixture.llm)
    }
    let initial = authorization(); precondition(initial())
    model.meetings[0].privacy.allowsCloudAI = false; precondition(!initial())
    model.meetings[0].privacy = privacy
    model.meetings[0].privacy.updatedAt = privacy.updatedAt.addingTimeInterval(1)
    precondition(!initial(), "OFF/ON reauthorized old operation")
    model.meetings = [meeting]
    let generation = authorization(); model.aiWorkspaceGeneration = UUID(); precondition(!generation())
    let workspace = authorization(); model.currentTeamID = "team"; precondition(!workspace())
    model.currentTeamID = nil; model.aiWorkspaceGeneration = UUID(); precondition(!workspace())
    let configuration = authorization(); RevisionAccessFixture.llm.model = "changed"; precondition(!configuration())
    RevisionAccessFixture.llm = .init()
    RevisionAccessFixture.configurationRevision = UUID()
    precondition(!configuration(), "Model OFF/ON revived old operation")
    let edited = authorization(); model.documents[0].slides[0].title = "別の編集"; precondition(!edited())
    model.documents = [document]
    let protected = authorization(); model.isStoreProtected = true; precondition(!protected()); model.isStoreProtected = false
    let restoring = authorization(); model.isRestoring = true; precondition(!restoring()); model.isRestoring = false
    let deleted = authorization(); model.documents = []; precondition(!deleted()); model.documents = [document]
    document.provenance?.isComplete = false; model.documents = [document]; precondition(!authorization()())
    RevisionAccessFixture.engine = .foundation
    let local = model.presentationRevisionAuthorization(for: document, engine: .foundation, llm: .init())
    precondition(local(), "Incomplete attribution must not require cloud use")
    document.companyTemplateID = UUID(); model.documents = [document]
    precondition(!model.presentationRevisionAuthorization(for: document, engine: .foundation, llm: .init())())
    print("Presentation revision access passed: production authorization, exact stored document, live source permissions/fingerprints, OFF/ON, workspace A-B-A, generation, model, protection, restore, deletion, incomplete-cloud refusal and local-only fallback; fixture configuration, no API")
  }
}
