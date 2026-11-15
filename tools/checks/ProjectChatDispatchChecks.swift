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
    print("ProjectChatDispatchChecks: passed (production send/cancel/delete + memory storage/model mocks, suspended retrieval, immediate resend, A-B-A, late callbacks/final/cleanup; no API, keys or files)")
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

  func persistNow(_ value: [ProjectChatThread], forKey: String) -> Bool { true }
  func space(id: UUID) -> MockProject? { MockProject(name: "架空プロジェクト") }
  func projectContext(question: String, projectID: UUID, cloud: Bool, budget: Int,
    selectedTargets: Set<ProjectCitation.Target>? = nil) async -> ProjectContextBuilder.Context {
    if suspendNextContext {
      suspendNextContext = false
      await withCheckedContinuation { contextContinuation = $0 }
    }
    return .init(text: "架空の資料", used: [])
  }
  func projectEvidenceStillAvailable(_ references: [ProjectCitation], projectID: UUID, cloud: Bool) async -> Bool { true }
  func projectEvidenceAllowed(_ target: ProjectCitation.Target, projectID: UUID, cloud: Bool) -> Bool { true }
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
  static func effectiveEngine(_ engine: MockEngine) -> MockEngine { engine }
  static func contextCharacterLimit(for engine: MockEngine) -> Int { 10_000 }
  static func contextCharacterLimit(for engine: MockEngine, llm: MockLLM, task: ContextTaskKind) -> Int { 10_000 }
  static func modelLabel(engine: MockEngine, llm: MockLLM) -> String? { nil }
  static func answer(engine: MockEngine, llm: MockLLM, question: String, scopeLabel: String, context: String,
                     history: String, onText: (@MainActor (String) -> Void)?, authorize: (@MainActor () -> Bool)? = nil) async -> AIAnswerResult {
    requests.append(question)
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
