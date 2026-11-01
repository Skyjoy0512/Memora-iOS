import Foundation

@main
@MainActor
struct ComposerRequestChecks {
  static func main() async {
    for change in 0..<9 {
      let fixture = Fixture()
      fixture.startGlobal()
      await until { AIAttachmentText.waiter != nil }
      switch change {
      case 0: fixture.model.aiConversationID = UUID()
      case 1: fixture.model.aiWorkspaceGeneration = UUID() // Includes A -> B -> A.
      case 2: fixture.model.composerDraft = "replacement"
      case 3:
        let extra = AIAttachment(id: UUID(), name: "second", url: URL(fileURLWithPath: "/second"))
        fixture.model.composerAttachment?.append(extra) // Primary ID is unchanged.
      case 4: fixture.model.askAIConfiguration.llm.modelID = "replacement"
      case 5: fixture.model.isToolsPresented = true
      case 6: fixture.model.selectedTab = .library
      case 7: fixture.model.activeNavigationPath = [.space(UUID())]
      default: fixture.model.composerMentions = [.init(pluginID: "new", label: "new", range: NSRange(location: 0, length: 0))]
      }
      let retainedDraft = fixture.model.composerDraft
      let retainedAttachment = fixture.model.composerAttachment
      // Dispatch validation must work even BEFORE SwiftUI's onChange runs.
      AIAttachmentText.resume()
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 0 && fixture.model.createdChats == 0)
      precondition(fixture.model.composerDraft == retainedDraft && fixture.model.composerAttachment == retainedAttachment)
    }

    do {
      let fixture = Fixture()
      fixture.startGlobal()
      fixture.revalidate() // A callback for the navigation that started this task is harmless.
      await until { AIAttachmentText.waiter != nil }
      AIAttachmentText.resume()
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 1 && fixture.model.composerDraft.isEmpty && fixture.model.composerAttachment == nil)
    }
    do {
      let fixture = Fixture()
      fixture.startGlobal()
      await until { AIAttachmentText.waiter != nil }
      fixture.cancel()
      AIAttachmentText.resume()
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 0 && fixture.model.composerAttachment != nil)
    }
    for stage in ["copy", "text"] {
      for change in 0..<7 {
        let fixture = Fixture(project: true)
        fixture.model.suspends = stage
        let request = fixture.request
        fixture.startProject(request)
        await until { fixture.model.waiter != nil }
        switch change {
        case 0: fixture.model.composerDraft = "replacement"
        case 1: fixture.model.composerAttachment?.additionalFiles?.removeLast()
        case 2: fixture.model.aiWorkspaceGeneration = UUID()
        case 3: fixture.model.activeNavigationPath = [.space(UUID())]
        case 4: fixture.model.askAIConfiguration.llm.modelID = "changed"
        case 5: fixture.scope = .space(UUID()) // A source can move without changing the navigation path.
        default: fixture.cancel()
        }
        let draft = fixture.model.composerDraft
        let attachment = fixture.model.composerAttachment
        fixture.model.resume()
        await until { !fixture.isPreparingAttachment }
        precondition(fixture.model.imports == 1 && fixture.model.sent == 0 && fixture.model.createdChats == 0)
        precondition(fixture.projectError == nil)
        precondition(fixture.model.composerDraft == draft && fixture.model.composerAttachment == attachment)
      }
    }
    do {
      let fixture = Fixture(project: true)
      let request = fixture.request
      fixture.model.composerDraft = "edited while approval was open"
      fixture.startProject(request)
      precondition(!fixture.isPreparingAttachment && fixture.model.imports == 0 && fixture.model.sent == 0)
    }
    do {
      let fixture = Fixture(project: true)
      let request = fixture.request
      fixture.scope = .space(UUID())
      fixture.startProject(request)
      precondition(!fixture.isPreparingAttachment && fixture.model.imports == 0 && fixture.model.sent == 0)
    }
    do {
      let fixture = Fixture(project: true)
      fixture.model.suspends = "text"
      fixture.startProject(fixture.request)
      await until { fixture.model.waiter != nil }
      fixture.model.composerDraft = "changed"
      fixture.revalidate()
      precondition(fixture.attachmentPreparationTask?.isCancelled == true)
      fixture.model.resume()
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 0)
    }
    do {
      let fixture = Fixture(project: true)
      fixture.startProject(fixture.request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.imports == 2 && fixture.model.sent == 1 && fixture.model.createdChats == 1)
      precondition(fixture.model.composerDraft.isEmpty && fixture.model.composerAttachment == nil)
      precondition(fixture.attachmentPreparationTask == nil && fixture.attachmentPreparationContext == nil)
    }
    print("ComposerRequestChecks PASS: production global/project dispatch; 23 suspended context races, cancellation, stale approval, multi-file success, cleanup")
  }

  static func until(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
      if condition() { return }
      await Task.yield()
    }
    preconditionFailure("Fixture did not reach suspension/completion")
  }
}

// Only dependencies and view storage are fixtures. The context, attachment
// values, import context and both production dispatch methods compile unchanged.
@MainActor
final class Fixture {
  var model = MemoraModel()
  var scope: AIQueryScope = .global
  var preparedAttachment: PreparedAIAttachment?
  var attachmentPreparationTask: Task<Void, Never>?
  var attachmentPreparationContext: AIComposerRequestContext?
  var isPreparingAttachment = false
  var projectError: String?
  var attachment: AIAttachment? { get { model.composerAttachment } set { model.composerAttachment = newValue } }
  var request: AIQuestionRequest {
    AIQuestionRequest(question: model.composerDraft, scope: scope, attachment: model.composerAttachment)
  }

  init(project: Bool = false) {
    model.composerDraft = "question"
    model.composerAttachment = AIAttachment(id: UUID(), name: "first", url: URL(fileURLWithPath: "/first"))
    if project {
      scope = .space(model.projectID)
      model.selectedTab = .library
      model.activeNavigationPath = [.space(model.projectID)]
      model.composerAttachment?.append(AIAttachment(id: UUID(), name: "second", url: URL(fileURLWithPath: "/second")))
    }
  }
  func startGlobal() { startGlobalAttachmentRequest(attachment!, question: model.composerDraft, pluginIDs: []) }
  func startProject(_ request: AIQuestionRequest) { startProjectRequest(request, allowsPaidRequest: true) }
  func cancel() { attachmentPreparationTask?.cancel() }
  func revalidate() { cancelStaleAttachmentPreparation() }
  // PRODUCTION_METHODS
}

@MainActor
final class MemoraModel {
  var composerDraft = ""
  var composerAttachment: AIAttachment?
  var composerMentions: [ComposerMention] = []
  var aiConversationID = UUID()
  var aiWorkspaceGeneration = UUID()
  var selectedTab = RootTab.askAI
  var activeNavigationPath: [LibraryRoute] = []
  var libraryPath: [LibraryRoute] { get { activeNavigationPath } set { activeNavigationPath = newValue } }
  var currentTeamID: UUID?
  var isRestoring = false
  var isStoreProtected = false
  var isToolsPresented = false
  var isAIChatResponding = false
  var askAIConfiguration = (engine: AIEngine.cloud, llm: LLMSelection(modelID: "first"))
  var transcriptionVocabulary: [String] = []
  var aiRequestRefusalMessage: String?
  var activeProjectChatID: UUID? { nil }
  var projectID = UUID()
  var sources: [UUID: Source] = [:]
  var suspends = ""
  var waiter: CheckedContinuation<Void, Never>?
  var imports = 0
  var sent = 0
  var createdChats = 0

  func space(id: UUID) -> MemoraSpace? { id == projectID ? MemoraSpace(id: id) : nil }
  func source(id: UUID) -> Source? { sources[id] }
  func projectChat(id: UUID) -> ProjectChatThread? { nil }
  func importProjectFile(_ url: URL, projectID: UUID?, importContext: LocalImportContext?, sourceTitle: String?,
                         originalURL: URL?, sourceMetadata: [String: String]?) async throws -> UUID? {
    imports += 1
    if suspends == "copy" && imports == 1 { await pause() }
    if Task.isCancelled { return nil }
    let id = UUID()
    sources[id] = Source(projectID: projectID, canProvideText: false)
    return id
  }
  func prepareProjectSource(_ id: UUID) async {
    if suspends == "text" && imports == 1 { await pause() }
    sources[id]?.canProvideText = true
  }
  func pause() async { await withCheckedContinuation { waiter = $0 } }
  func resume() { let waiting = waiter; waiter = nil; waiting?.resume() }
  func createProjectChat(projectID: UUID) -> UUID? { createdChats += 1; return UUID() }
  func sendProjectChat(_ id: UUID, question: String, allowsPaidRequest: Bool, pluginIDs: [String]) -> Bool { sent += 1; return true }
  func openProjectChat(_ id: UUID) { activeNavigationPath = [.projectChat(id)] }
  func sendAIChat(_ question: String, attachment: AIAttachment, pluginIDs: [String], preparedAttachment: PreparedAIAttachment) -> Bool { sent += 1; return true }
}

struct MemoraSpace: Equatable { var id: UUID }
struct Source { var projectID: UUID?; var canProvideText: Bool; var privacy = true }
struct ProjectChatThread { var id: UUID; var projectID: UUID }
enum RootTab { case library, home, askAI }
enum LibraryRoute: Equatable { case space(UUID), projectChat(UUID), projectSource(UUID) }
enum AIEngine { case cloud, onDevice }
struct LLMSelection: Equatable { var modelID: String }
enum AIEngineService { static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine } }
struct ModelCapabilities { static func resolve(llm: LLMSelection) -> ModelCapabilities { Self() } }
enum DeepContextPolicy { static func task(for question: String) -> Int { 0 } }
enum AgentAttachmentContext {
  static func characterBudget(capabilities: ModelCapabilities, task: Int) -> Int { 100 }
  static func content(attachment: AIAttachment, prepared: PreparedAIAttachment, maximumCharacters: Int) -> String? { "body" }
}
struct PreparedAIAttachment {
  var preparedQuestion: String
  var failure: String? { nil }
  func matches(_ attachment: AIAttachment) -> Bool { false }
}
@MainActor
enum AIAttachmentText {
  static var waiter: CheckedContinuation<Void, Never>?
  static func prepare(_ attachment: AIAttachment, question: String, maximumCharacters: Int, vocabulary: [String]) async -> PreparedAIAttachment {
    await withCheckedContinuation { waiter = $0 }
    return PreparedAIAttachment(preparedQuestion: question)
  }
  static func resume() { let waiting = waiter; waiter = nil; waiting?.resume() }
}
enum RecordAccessPolicy {
  enum Purpose { case cloudAI }
  static func allows(_ privacy: Bool, purpose: Purpose) -> Bool { privacy }
}
