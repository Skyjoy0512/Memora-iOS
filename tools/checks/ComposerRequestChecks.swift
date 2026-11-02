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
      for change in 0..<8 {
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
        case 5: fixture.scope = .space(UUID())
        case 6: fixture.model.visibleProjectID = UUID() // The async closure still holds the old view scope.
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
    do {
      let fixture = Fixture(project: true)
      fixture.model.composerAttachment = nil
      fixture.model.askAIConfiguration.engine = .onDevice
      fixture.model.composerDraft = "https://example.org/article?utm_source=chat https://EXAMPLE.org/article#section"
      fixture.startProject(fixture.request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 1 && fixture.model.sources.count == 1 && fixture.model.linkPreparations == 1)
      let source = fixture.model.projectSources[0]
      precondition(source.projectID == fixture.model.projectID && source.kind == .web)
      precondition(source.originalURL?.absoluteString == "https://example.org/article" && !source.privacy)
    }
    do {
      let fixture = Fixture(project: true)
      fixture.model.askAIConfiguration.engine = .onDevice
      fixture.model.composerDraft = "https://example.org/reference.pdf"
      fixture.startProject(fixture.request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 1 && fixture.model.imports == 2 && fixture.model.sources.count == 3)
    }
    for youtube in [false, true] {
      let fixture = Fixture(project: true)
      fixture.model.composerAttachment = nil
      fixture.model.composerDraft = youtube ? "https://youtu.be/dQw4w9WgXcQ" : "https://example.org/blocked"
      fixture.model.linkReadable = false
      fixture.model.linkFailure = youtube ? "Add a subtitle file" : "Unable to read the page"
      fixture.startProject(fixture.request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 0 && fixture.model.sources.count == 1)
      precondition(fixture.projectError == fixture.model.linkFailure && !fixture.model.composerDraft.isEmpty)
      let source = fixture.model.projectSources[0]
      precondition(source.kind == (youtube ? .youtube : .web) && !source.privacy)
    }
    do {
      let fixture = Fixture(project: true)
      fixture.model.composerAttachment = nil
      fixture.model.composerDraft = "https://example.org/private"
      let request = fixture.request
      fixture.startProject(request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 0 && fixture.model.sources.count == 1 && fixture.projectError != nil)
      precondition(!fixture.model.projectSources[0].privacy && fixture.model.composerDraft == request.question)
      fixture.model.activeNavigationPath = [.space(fixture.model.projectID)]
      fixture.model.askAIConfiguration.engine = .onDevice
      fixture.startProject(fixture.request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 1 && fixture.model.sources.count == 1) // Retry reuses the same URL.
    }
    for change in 0..<3 {
      let fixture = Fixture(project: true)
      fixture.model.composerAttachment = nil
      fixture.model.askAIConfiguration.engine = .onDevice
      fixture.model.composerDraft = "https://example.org/one https://example.org/two"
      fixture.model.suspends = "link"
      fixture.startProject(fixture.request)
      await until { fixture.model.waiter != nil }
      switch change {
      case 0: fixture.model.composerDraft = "replacement"
      case 1: fixture.model.aiWorkspaceGeneration = UUID()
      default: fixture.cancel()
      }
      let draft = fixture.model.composerDraft
      fixture.model.resume()
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 0 && fixture.model.sources.count == 1 && fixture.model.linkPreparations == 1)
      precondition(fixture.model.composerDraft == draft && fixture.projectError == nil)
    }
    do {
      let fixture = Fixture(project: true)
      fixture.model.composerAttachment = nil
      fixture.model.composerDraft = "https://EXAMPLE.org/existing?utm_source=chat"
      let url = URL(string: "https://example.org/existing")!
      let existing = ProjectSource(projectID: fixture.model.projectID, kind: .web, title: "kept", originalURL: url, canProvideText: true, privacy: true)
      fixture.model.sources[existing.id] = existing
      fixture.model.linkPrivacy = true
      fixture.startProject(fixture.request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sent == 1 && fixture.model.sources.count == 1)
      precondition(fixture.model.sources[existing.id]?.title == "kept" && fixture.model.sources[existing.id]?.privacy == true)
    }
    do {
      let fixture = Fixture(project: true)
      fixture.model.composerAttachment = nil
      fixture.model.composerDraft = "https://127.0.0.1/private https://name:secret@example.org/private http://example.org/plain"
      fixture.startProject(fixture.request)
      await until { !fixture.isPreparingAttachment }
      precondition(fixture.model.sources.isEmpty && fixture.model.linkPreparations == 0)
    }
    print("ComposerRequestChecks PASS: production global/project dispatch; 25 suspended context races plus pasted-link routing, cancellation, stale approval, multi-file success, cleanup")
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
      model.visibleProjectID = model.projectID
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
  var visibleProjectID: UUID?
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
  var sources: [UUID: ProjectSource] = [:]
  var projectSources: [ProjectSource] { Array(sources.values) }
  var linkPreparations = 0
  var linkReadable = true
  var linkFailure: String?
  var linkPrivacy = false
  var suspends = ""
  var waiter: CheckedContinuation<Void, Never>?
  var imports = 0
  var sent = 0
  var createdChats = 0

  func space(id: UUID) -> MemoraSpace? { id == projectID ? MemoraSpace(id: id) : nil }
  func source(id: UUID) -> ProjectSource? { sources[id] }
  func storeProjectSource(_ source: ProjectSource, removing: [String] = []) -> Bool {
    precondition(removing.isEmpty) // Draft commits run against real SQLite in the storage checks.
    sources[source.id] = source; return true
  }
  func persistBatch(_ build: () throws -> [(key: String, data: Data)], removing: [String]) -> Bool {
    preconditionFailure("Composer fixtures do not commit editor drafts")
  }
  func scheduleProjectSourcePreparation(_ id: UUID) {}
  func projectChat(id: UUID) -> ProjectChatThread? { nil }
  func importProjectFile(_ url: URL, projectID: UUID?, importContext: LocalImportContext?, sourceTitle: String?,
                         originalURL: URL?, sourceMetadata: [String: String]?) async throws -> UUID? {
    imports += 1
    if suspends == "copy" && imports == 1 { await pause() }
    if Task.isCancelled { return nil }
    let id = UUID()
    sources[id] = ProjectSource(id: id, projectID: projectID, kind: .document, title: sourceTitle ?? "file", canProvideText: false, privacy: true)
    return id
  }
  func prepareProjectSource(_ id: UUID) async {
    if sources[id]?.kind == .web || sources[id]?.kind == .youtube {
      linkPreparations += 1
      if suspends == "link" && linkPreparations == 1 { await pause() }
      sources[id]?.canProvideText = linkReadable
      sources[id]?.errorInformation = linkFailure
      sources[id]?.privacy = linkPrivacy
      return
    }
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
struct ProjectSource {
  var id = UUID()
  var projectID: UUID?
  var kind: Kind
  var title: String
  var originalURL: URL?
  var canProvideText = false
  var privacy = false
  var errorInformation: String?
  enum Kind { case web, youtube, document }
}
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
