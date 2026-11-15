import Foundation

@main @MainActor
struct ResidentLifecycleChecks {
  static func main() async {
    for phase in ["model", "tool"] {
      for change in 0..<12 {
        let model = fixture()
        let agent = model.residentAgents[0]
        let gate = Gate()
        var turns = 0
        CloudAgentSession.nextTurn = {
          turns += 1
          if phase == "model" { await gate.pause() }
          return turns == 1 && phase == "tool"
            ? AgentTurn(text: "", toolCalls: [call(), call()]) : AgentTurn(text: "確定した回答", toolCalls: [])
        }
        model.readTool = { await gate.pause(); return .init(text: "読む本文") }
        let job = Task { await model.runResident(agent) }
        await gate.entered()
        switch change {
        case 0: model.residentAgents[0].isEnabled = false
        case 1:
          model.residentAgents[0].isEnabled = false
          model.residentAgents[0].isEnabled = true
        case 2: model.deleteResident(agent.id)
        case 3: model.residentAgents[0].instructions = "変更した指示"
        case 4: model.cancelResident(agent.id)
        case 5: job.cancel()
        case 6: model.aiWorkspaceGeneration = UUID()
        case 7: model.isRestoring = true; model.isRestoring = false
        case 8: model.isStoreProtected = true; model.isStoreProtected = false
        case 9: model.residentAccessRevision = "失効した許可"
        case 10: model.enabledAgentTools = []
        default: model.registeredLLMs.revision = UUID()
        }
        gate.release()
        precondition(awaitedFalse: await job.value)
        precondition(model.aiMessages.isEmpty && model.history.isEmpty)
        precondition(model.residentAgents.first?.lastRunAt == nil)
        precondition(model.residentJobs.isEmpty && model.residentRunRequests.isEmpty && model.runningResidentIDs.isEmpty)
        precondition(model.toolCalls == (phase == "tool" ? 1 : 0))
        precondition(UNUserNotificationCenter.current().notifications.isEmpty)
      }
    }

    // Waiting automatic work carries its original authorization, including OFF -> ON.
    for change in 0..<4 {
      let model = fixture()
      var second = model.residentAgents[0]; second.id = UUID(); second.name = "後続"
      model.residentAgents.append(second)
      let gate = Gate()
      var sessions = 0
      CloudAgentSession.nextTurn = { sessions += 1; await gate.pause(); return .init(text: "最初の回答", toolCalls: []) }
      model.runResidentsAfterMeeting(UUID())
      await gate.entered()
      switch change {
      case 0: model.deleteResident(second.id)
      case 1: model.residentAgents[1].isEnabled = false; model.residentAgents[1].isEnabled = true
      case 2: model.residentAgents[1].role = "変更後"
      default: model.cancelResident(second.id)
      }
      gate.release()
      for _ in 0..<50 { await Task.yield() }
      precondition(sessions == 1 && model.history.count == 1)
      precondition(model.residentAgents.first(where: { $0.id == second.id })?.lastRunAt == nil)
    }

    // An explicit editor run works with scheduling off and its unsaved draft.
    let manual = fixture()
    manual.residentAgents[0].isEnabled = false
    var draft = manual.residentAgents[0]; draft.instructions = "今回だけの指示"
    CloudAgentSession.nextTurn = { .init(text: "回答\n提案: 次に依頼する", toolCalls: []) }
    let posted = await manual.runResident(draft)
    precondition(posted && manual.history.count == 1 && manual.aiMessages[0].suggestions == ["次に依頼する"])
    precondition(manual.residentAgents[0].lastRunAt != nil)
    precondition(!manual.residentAgents[0].isEnabled && manual.residentAgents[0].instructions != draft.instructions)
    precondition(CloudAgentSession.lastInstructions.contains("今回だけの指示"))

    let settled = manual.residentAgents[0].lastRunAt
    manual.updateResident(draft)
    precondition(manual.residentAgents[0].lastRunAt == settled)

    // A stale completion cannot release the single-flight guard before it settles.
    let single = fixture(); let gate = Gate()
    CloudAgentSession.nextTurn = { await gate.pause(); return .init(text: "古い回答", toolCalls: []) }
    let old = Task { await single.runResident(single.residentAgents[0]) }
    await gate.entered(); single.cancelResident(single.residentAgents[0].id)
    let overlap = await single.runResident(single.residentAgents[0]); precondition(!overlap)
    gate.release(); precondition(awaitedFalse: await old.value)
    CloudAgentSession.nextTurn = { .init(text: "新しい回答", toolCalls: []) }
    let replacement = await single.runResident(single.residentAgents[0])
    precondition(replacement && single.history == ["新しい回答"] && single.residentJobs.isEmpty)

    // Notification suspension happens after a valid result commits; disable cannot send a stale notice.
    for phase in ["settings", "add"] {
      let model = fixture(); UIApplication.shared.applicationState = .background
      let center = UNUserNotificationCenter.current(); let gate = Gate()
      if phase == "settings" { center.settingsWait = { await gate.pause() } }
      else { center.addWait = { await gate.pause() } }
      CloudAgentSession.nextTurn = { .init(text: "完了済みの回答", toolCalls: []) }
      let job = Task { await model.runResident(model.residentAgents[0]) }
      await gate.entered()
      precondition(model.history.count == 1)
      model.residentAgents[0].isEnabled = false
      gate.release(); _ = await job.value
      precondition(center.notifications.isEmpty)
      precondition(center.addCount == (phase == "add" ? 1 : 0))
      precondition(model.history.count == 1)
    }
    print("PASS: production resident lifecycle; 24 model/tool suspension races, 4 stale automatic queues, manual disabled/draft run, cancellation single-flight ownership, and notification settings/add races. LLM, OS scheduling/notifications and model persistence are fixtures; no API requests.")
  }

  static func call() -> AgentToolCall { .init(id: UUID().uuidString, name: "read_record", arguments: [:]) }
  static func fixture() -> MemoraModel {
    CloudAgentSession.nextTurn = { .init(text: "回答", toolCalls: []) }
    UIApplication.shared.applicationState = .active
    UNUserNotificationCenter.current().reset()
    let model = MemoraModel()
    model.residentAgents = [ResidentAgent(id: UUID(), name: "朝の要点", role: "読む", instructions: "実際の記録を読む",
      symbol: .calendar, trigger: .afterMeeting, isEnabled: true)]
    return model
  }
}

func precondition(awaitedFalse value: Bool) { precondition(!value) }

@MainActor final class Gate {
  var continuation: CheckedContinuation<Void, Never>?
  var arrival: CheckedContinuation<Void, Never>?
  var didEnter = false
  func pause() async {
    didEnter = true; arrival?.resume(); arrival = nil
    await withCheckedContinuation { continuation = $0 }
  }
  func entered() async {
    if !didEnter { await withCheckedContinuation { arrival = $0 } }
  }
  func release() { continuation?.resume(); continuation = nil }
}

@MainActor final class MemoraModel {
  var residentAgents: [ResidentAgent] = [] { didSet { residentDefinitionsDidChange(from: oldValue) } }
  var residentJobs: [UUID: Task<Bool, Never>] = [:]
  var residentRunRequests: [UUID: ResidentRunRequest] = [:]
  var residentDefinitionRevisions: [UUID: UUID] = [:]
  var residentEnvironmentRevision = UUID()
  var residentRunFailures: [UUID: String] = [:]
  var runningResidentIDs: Set<UUID> = []
  var currentTeamID: String?
  var isRestoring = false { didSet { if oldValue != isRestoring { invalidateResidentEnvironment() } } }
  var isStoreProtected = false { didSet { if oldValue != isStoreProtected { invalidateResidentEnvironment() } } }
  var aiWorkspaceGeneration = UUID() { didSet { invalidatePendingResidents() } }
  var summaryConfigurationRevision = UUID()
  var registeredLLMs = RegisteredLLMStore()
  var residentAccessRevision = "許可した記録" { didSet { invalidatePendingResidents() } }
  var enabledAgentTools = AgentTool.residentTools { didSet { invalidateResidentEnvironment() } }
  var askAIConfiguration = Configuration()
  var aiMessages: [AIChatMessage] = []
  var history: [String] = []
  var toolCalls = 0
  var readTool: () async -> AgentToolOutcome = { .init(text: "本文") }
  func allowsRecordAccess(_ id: UUID, purpose: Purpose) -> Bool { true }
  enum Purpose { case automaticAgent }
  func personalContext(for: String, budget: Int, includesHistory: Bool) -> String { "" }
  func meeting(id: UUID) -> Meeting? { nil }
  func agentMessage(_ id: UUID) -> AIChatMessage? { aiMessages.first { $0.id == id } }
  func updateAgentMessage(_ id: UUID, update: (inout AIChatMessage) -> Void) {
    guard let index = aiMessages.firstIndex(where: { $0.id == id }) else { return }
    update(&aiMessages[index])
  }
  func saveAIExchange(question: String, answer: String, scopeLabel: String, engineLabel: String, modelLabel: String) { history.append(answer) }
  func runAgentTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope, automaticAccess: Bool) async -> AgentToolOutcome {
    toolCalls += 1; return await readTool()
  }
}

struct LLMSelection: Equatable { var modelID = "fixture-model"; var isMemoraIntelligence = false; var keychainAccount = "fixture-account"; var modelLabel = "fixture" }
struct Configuration { var engine = AIEngine.cloud; var llm = LLMSelection() }
enum AIEngine { case cloud }
enum AIEngineService { static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine } }
enum KeychainStore { static func string(forKey: String) -> String? { "fixture-only" } }
final class RegisteredLLMStore { var revision = UUID() }
struct Meeting { var displayTitle = "fixture" }
enum AgentTool: String { case readRecord = "read_record", listTasks = "list_tasks"; static var residentTools: [Self] { [.readRecord, .listTasks] }; var icon: MemoraIcon { .calendar } }
enum AIChatScope { case all; var scopeLabel: String { "すべて" } }
struct AIAnswerDetails { var scopeLabel: String; var engineLabel: String; var modelLabel: String; var sourceCount: Int; var generatedAt: Date }
struct AIChatMessage {
  enum Role { case assistant }
  var role: Role; var text: String; var isThinking: Bool
  var id = UUID(); var isAgentReply = false; var residentName: String?; var residentAgentID: UUID?; var residentSymbol: MemoraIcon?
  var suggestions: [String] = []; var finishedAt: Date?; var details: AIAnswerDetails?; var agentSteps: [Step] = []
  struct Step { var icon: MemoraIcon }
}
@MainActor final class CloudAgentSession {
  static var nextTurn: () async throws -> AgentTurn = { .init(text: "", toolCalls: []) }
  static var lastInstructions = ""
  private var authorize: (@MainActor () -> Bool)?
  init?(llm: LLMSelection, system: String, tools: [AgentTool], priority: SummaryRequestAdmission.Priority = .interactive,
        authorize: (@MainActor () -> Bool)? = nil) {
    precondition(priority == .background, "Resident work lost its background admission priority")
    self.authorize = authorize
    Self.lastInstructions = system
  }
  func next() async throws -> AgentTurn {
    guard authorize?() ?? true else { throw AIAnswerFailure.contextChanged }
    return try await Self.nextTurn()
  }
  func addUserMessage(_ text: String) {}
  func addToolResults(_ results: [(call: AgentToolCall, outcome: AgentToolOutcome)]) {}
}
struct GmailService { @MainActor static var shared = GmailService(); var isConnected: Bool { false } }
enum ReadabilityGuide { static var rules = "" }
@MainActor final class UIApplication {
  enum State { case active, background }
  static let shared = UIApplication(); var applicationState = State.active
}
@MainActor final class UNUserNotificationCenter {
  static let shared = UNUserNotificationCenter()
  static func current() -> UNUserNotificationCenter { shared }
  enum Status { case authorized, provisional }
  struct Settings { var authorizationStatus = Status.authorized }
  var settingsWait: (() async -> Void)?; var addWait: (() async -> Void)?
  var notifications: Set<String> = []; var addCount = 0
  func reset() { settingsWait = nil; addWait = nil; notifications = []; addCount = 0 }
  func notificationSettings() async -> Settings { await settingsWait?(); return Settings() }
  func add(_ request: UNNotificationRequest) async throws { addCount += 1; await addWait?(); notifications.insert(request.identifier) }
  func removePendingNotificationRequests(withIdentifiers ids: [String]) { notifications.subtract(ids) }
  func removeDeliveredNotifications(withIdentifiers ids: [String]) { notifications.subtract(ids) }
}
final class UNMutableNotificationContent { var title = ""; var body = ""; var userInfo: [String: String] = [:] }
struct UNNotificationRequest { var identifier: String; var content: UNMutableNotificationContent; var trigger: String? }
@MainActor final class BGTaskScheduler { static let shared = BGTaskScheduler(); func cancel(taskRequestWithIdentifier: String) {}; func submit(_ request: BGAppRefreshTaskRequest) throws {} }
final class BGAppRefreshTaskRequest { init(identifier: String) {}; var earliestBeginDate: Date? }
final class BGAppRefreshTask { var expirationHandler: (() -> Void)?; func setTaskCompleted(success: Bool) {} }
