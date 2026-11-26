import Foundation

@main
@MainActor
struct ProjectChatDispatchChecks {
  static func main() async {
    let model = MemoraModel()
    let id = UUID(), project = UUID()
    let saved = ProjectChatTurn(role: .assistant, text: "保存済みの回答")
    model.projectChats = [ProjectChatThread(id: id, projectID: project, title: "架空", messages: [saved])]

    model.suspendNextContext = true
    precondition(model.sendProjectChat(id, question: "old-context"))
    let oldContextJob = model.projectChatJobs[id]!
    await until { model.contextContinuation != nil }
    model.cancelProjectChat(id)
    precondition(model.sendProjectChat(id, question: "replacement"))
    let replacementID = model.projectChat(id: id)!.pendingMessageID!
    let replacementJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["replacement"] != nil }
    let continuation = model.contextContinuation
    model.contextContinuation = nil
    continuation?.resume()
    await oldContextJob.value
    precondition(AIEngineService.requests == ["replacement"])
    precondition(model.projectChatRequestIDs[id] == replacementID && model.projectChatJobs[id] != nil)
    precondition(model.projectChatBusyIDs.contains(id) && model.projectChatPartialAnswers[id] == "partial replacement")
    AIEngineService.finish("replacement", text: "新しい完了回答")
    await replacementJob.value
    precondition(model.projectChat(id: id)?.messages.last?.text == "新しい完了回答")
    precondition(!model.projectChatBusyIDs.contains(id) && model.projectChatJobs[id] == nil)
    precondition(model.projectChat(id: id)?.messages.first == saved)

    precondition(model.sendProjectChat(id, question: "old-workspace"))
    let oldWorkspaceJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["old-workspace"] != nil }
    let oldGeneration = model.aiWorkspaceGeneration
    model.currentTeamID = "fixture-B"
    model.invalidateAIWorkspaceExecution()
    model.currentTeamID = nil
    model.invalidateAIWorkspaceExecution()
    precondition(model.aiWorkspaceGeneration != oldGeneration)
    precondition(model.projectChat(id: id)?.pendingMessageID == nil)
    precondition(model.sendProjectChat(id, question: "returned-workspace"))
    let returnedJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["returned-workspace"] != nil }
    let messagesBeforeLateReply = model.projectChat(id: id)!.messages
    // Deliver callbacks from the current task to avoid relying solely on the
    // cancelled flag of the original provider task.
    AIEngineService.callbacks["old-workspace"]?("stale text")
    AIEngineService.finish("old-workspace", text: "stale final")
    await oldWorkspaceJob.value
    precondition(model.projectChat(id: id)?.messages == messagesBeforeLateReply)
    precondition(model.projectChatPartialAnswers[id] == "partial returned-workspace")
    precondition(model.projectChatBusyIDs.contains(id) && model.projectChatJobs[id] != nil)
    AIEngineService.finish("returned-workspace", text: "戻った後の回答")
    await returnedJob.value
    precondition(model.projectChat(id: id)?.messages.last?.text == "戻った後の回答")

    precondition(model.sendProjectChat(id, question: "deleted"))
    let deletedJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["deleted"] != nil }
    precondition(model.deleteProjectChat(id))
    AIEngineService.callbacks["deleted"]?("must not reappear")
    AIEngineService.finish("deleted", text: "must not recreate deleted chat")
    await deletedJob.value
    precondition(model.projectChats.isEmpty && model.projectChatJobs.isEmpty && model.projectChatRequestIDs.isEmpty)
    precondition(model.projectChatStages.isEmpty && model.projectChatPartialAnswers.isEmpty && model.projectChatBusyIDs.isEmpty)
    precondition(AIEngineService.pending.isEmpty)

    let target = ProjectCitation.Target.meeting(UUID())
    let photo = ProjectCitation(target: target, title: "ホワイトボード", excerpt: "端末内の写真の文字",
      photo: .init(name: "private.jpg", byteCount: 1_024, modifiedAt: .now, textReadAt: .now))
    let ordinary = ProjectCitation(target: target, title: "議事録", excerpt: "参照を許可した資料の文字")
    let localTurn = ProjectChatTurn(role: .assistant, text: photo.excerpt, contextReferences: [photo])
    model.projectChats = [ProjectChatThread(id: id, projectID: project, title: "会話",
      messages: [ProjectChatTurn(role: .user, text: "写真の確認"), localTurn])]
    model.contextReferences = [ordinary]
    precondition(model.sendProjectChat(id, question: "local-follow-up"))
    let localJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["local-follow-up"] != nil }
    precondition(AIEngineService.histories["local-follow-up"]?.contains(photo.excerpt) == true)
    AIEngineService.finish("local-follow-up", text: "写真を含む会話の続き")
    await localJob.value
    let derivedTurn = model.projectChat(id: id)?.messages.last
    precondition(derivedTurn?.contextReferences == [ordinary, photo] && derivedTurn?.cloudReplayAuthorizationVersion == nil)

    model.revokedEvidence = [photo]
    precondition(model.sendProjectChat(id, question: "after-revocation"))
    let revokedJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["after-revocation"] != nil }
    precondition(AIEngineService.histories["after-revocation"] == "")
    AIEngineService.finish("after-revocation", text: ordinary.excerpt)
    await revokedJob.value

    model.askAIConfiguration.engine = .cloud
    precondition(model.sendProjectChat(id, question: "cloud-follow-up", allowsPaidRequest: true))
    let cloudJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["cloud-follow-up"] != nil }
    precondition(AIEngineService.histories["cloud-follow-up"] == "")
    AIEngineService.finish("cloud-follow-up", text: ordinary.excerpt)
    await cloudJob.value
    precondition(model.projectChat(id: id)?.messages.last?.cloudReplayAuthorizationVersion == 1)
    precondition(model.sendProjectChat(id, question: "authorized-cloud-follow-up", allowsPaidRequest: true))
    let replayJob = model.projectChatJobs[id]!
    await until { AIEngineService.pending["authorized-cloud-follow-up"] != nil }
    precondition(AIEngineService.histories["authorized-cloud-follow-up"]?.contains("ユーザー: cloud-follow-up") == true)
    AIEngineService.finish("authorized-cloud-follow-up", text: ordinary.excerpt)
    await replayJob.value
    print("ProjectChatDispatchChecks: passed (production dispatch, generation, transitive evidence, revocation and cloud replay; model and persistence fixtures)")
  }

  private static func until(_ predicate: () -> Bool) async {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    preconditionFailure("Mock request did not arrive")
  }
}

// Only dependency surfaces are mocked; the send, cancellation, generation and
// cleanup implementations are compiled directly from the app extensions.
@MainActor
final class MemoraModel {
  enum StorageKey { static let projectChats = "isolated-fixture" }
  var projectChats: [ProjectChatThread] = []
  var aiWorkspaceGeneration = UUID()
  var projectChatRequestIDs: [UUID: UUID] = [:]
  var projectChatJobs: [UUID: Task<Void, Never>] = [:]
  var projectChatBusyIDs: Set<UUID> = []
  var projectChatStages: [UUID: String] = [:]
  var projectChatPartialAnswers: [UUID: String] = [:]
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  var activeNavigationPath: [LibraryRoute] = []
  var libraryPath: [LibraryRoute] = []
  var selectedTab = RootTab.library
  var askAIConfiguration = MockConfiguration()
  var enabledAgentTools: [AgentTool] = []
  var suspendNextContext = false
  var contextContinuation: CheckedContinuation<Void, Never>?
  var contextReferences: [ProjectCitation] = []
  var revokedEvidence: Set<ProjectCitation> = []

  func persistNow(_ value: [ProjectChatThread], forKey: String) -> Bool { true }
  func space(id: UUID) -> MockProject? { MockProject(name: "架空プロジェクト") }
  func projectContext(question: String, projectID: UUID, cloud: Bool, budget: Int,
    selectedTargets: Set<ProjectCitation.Target>? = nil) async -> ProjectContextBuilder.Context {
    if suspendNextContext {
      suspendNextContext = false
      await withCheckedContinuation { contextContinuation = $0 }
    }
    return .init(text: "架空の資料", used: contextReferences)
  }
  func projectEvidenceStillAvailable(_ references: [ProjectCitation], projectID: UUID, cloud: Bool) async -> Bool {
    revokedEvidence.isDisjoint(with: references)
  }
  func projectCitationAllowed(_ citation: ProjectCitation, projectID: UUID, cloud: Bool) -> Bool { true }
  func projectMentionSelection(_ ids: [String], projectID: UUID) -> ProjectMentionSelection? {
    guard ids.isEmpty else { return nil }
    return ProjectMentionSelection(pluginIDs: [], toolNames: ProjectMentionSelection.readingTools, guidance: "")
  }
  func answerProjectAgent(question: String, projectID: UUID, llm: MockLLM,
    initialContext: ProjectContextBuilder.Context, history: String, selection: ProjectMentionSelection,
    historyEvidence: [ProjectCitation], characterBudget: Int,
    isCurrent: @escaping @MainActor () -> Bool, onText: @escaping @MainActor (String) -> Void,
    onStage: @escaping @MainActor (String) -> Void) async -> ScopedAgentAnswer {
    preconditionFailure("This fixture must not invoke a tool-calling model")
  }
}

enum RootTab { case library }
enum LibraryRoute: Equatable { case projectChat(UUID) }
enum AgentTool: String { case searchRecords = "search_records", readRecord = "read_record", listTasks = "list_tasks" }
struct MockProject { var name: String }
struct MockLLM { var supportsToolCalling = false; var isMemoraIntelligence = false }
struct MockConfiguration { var engine = MockEngine.local; var llm = MockLLM() }
enum MockEngine { case local, cloud; var label: String { "fixture" } }
enum ProjectContextBuilder {
  struct Context { var text: String; var used: [ProjectCitation] }
  static func cited(_ text: String, from: [ProjectCitation]) -> [ProjectCitation] { [] }
}

enum ContextTaskKind { case agent }
@MainActor
enum AIEngineService {
  static var pending: [String: CheckedContinuation<AIAnswerResult, Never>] = [:]
  static var callbacks: [String: @MainActor (String) -> Void] = [:]
  static var requests: [String] = []
  static var histories: [String: String] = [:]
  static func effectiveEngine(_ engine: MockEngine) -> MockEngine { engine }
  static func contextCharacterLimit(for engine: MockEngine) -> Int { 10_000 }
  static func contextCharacterLimit(for engine: MockEngine, llm: MockLLM, task: ContextTaskKind) -> Int { 10_000 }
  static func modelLabel(engine: MockEngine, llm: MockLLM) -> String? { nil }
  static func answer(engine: MockEngine, llm: MockLLM, question: String, scopeLabel: String, context: String,
                     history: String, onText: (@MainActor (String) -> Void)?, authorize: (@MainActor () -> Bool)? = nil) async -> AIAnswerResult {
    requests.append(question)
    histories[question] = history
    callbacks[question] = onText
    onText?("partial " + question)
    return await withCheckedContinuation { pending[question] = $0 }
  }
  static func finish(_ question: String, text: String) {
    let continuation = pending.removeValue(forKey: question)
    callbacks.removeValue(forKey: question)
    continuation?.resume(returning: .answer(text))
  }
}
