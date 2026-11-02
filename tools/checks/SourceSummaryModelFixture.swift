import Foundation

// Engines, registry data and model state are fixtures. Admission, source-summary
// orchestration, source storage/recovery, SQLite and original text reads are real.
@MainActor final class MemoraModel {
  var store: LocalStore
  var storeURL: URL
  var projectSources: [ProjectSource] = [] { didSet { projectSourceIndex.invalidate() } }
  var projectSourceIndex = IdentifiableIndex<ProjectSource>()
  var projectSourceProcessingIDs: Set<UUID> = []
  var sourcePreparationJobs: [UUID: (id: UUID, task: Task<Void, Never>)] = [:]
  var spaces: [MemoraSpace] = []
  var currentTeamID: String? { didSet { if oldValue != currentTeamID { aiWorkspaceGeneration = UUID() } } }
  var aiWorkspaceGeneration = UUID()
  var isRestoring = false
  var isStoreProtected = false
  var failurePresentation = PersistenceFailurePresentation()
  var summaryConfigurationIdentity = [UUID(), UUID()]
  var summaryPreferences = SummaryPreferences()
  var registeredLLMs = SourceSummaryRegistry()
  var aiSelection = LLMSelection(modelID: "settings")
  var askAIConfiguration: (engine: AIEngine, llm: LLMSelection) = (.foundation, .init(modelID: "ask-ai"))
  var settingsAIConfiguration: (engine: AIEngine, llm: LLMSelection) = (.foundation, .init(modelID: "settings"))
  var choices = SummaryTemplateChoice.builtInChoices
  var tasks: [String] = []
  enum StorageKey { static let projectSources = "memoraProjectSources" }

  init(storeURL: URL) throws {
    self.storeURL = storeURL
    store = LocalStore(fileURL: storeURL)
    try store.prepare()
  }
  func space(id: UUID) -> MemoraSpace? { spaces.first { $0.id == id } }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func invalidateProjectEvidence(_ targets: [ProjectCitation.Target]) {}
  func summaryChoice(_ id: String) -> SummaryTemplateChoice? {
    id == SummaryTemplateChoice.adaptive.id ? .adaptive : choices.first { $0.id == id }
  }
  func handlingPersistenceFailureLocally<Value>(_ operation: () throws -> Value) rethrows -> Value {
    try failurePresentation.locallyHandled(operation)
  }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do { try store.write(key, data: JSONEncoder().encode(value)); return true }
    catch { return false }
  }
  func persistBatch(_ build: () throws -> [(key: String, data: Data)], removing: [String] = []) -> Bool {
    do { try store.applyBatch(writes: build(), removing: removing); return true }
    catch { return false }
  }
}

struct SourceSummaryRegistry {
  var models: [SourceSummaryRegisteredModel] = []
}
struct SourceSummaryRegisteredModel {
  var id: UUID
  var selection: LLMSelection
}
enum AIEngine: String, Codable { case automatic, foundation, local, cloud, memora }
struct LLMSelection: Equatable { var modelID: String }
enum AIEngineService {
  static func effectiveEngine(_ engine: AIEngine) -> AIEngine {
    engine == .memora ? .cloud : (engine == .automatic ? .foundation : engine)
  }
}
enum MemoraFormat {
  static func duration(_ time: TimeInterval) -> String { String(time) }
}
struct MeetingSummary {
  var markdown: String
  var actions: [String] = ["fixture action must never become a task"]
}

@MainActor enum MeetingSummarizer {
  static var calls: [(input: MeetingSummaryInput, engine: AIEngine, llm: LLMSelection)] = []
  static var outcome: Result<MeetingSummary, AIAnswerFailure> = .success(.init(markdown: "生成された要約"))
  static var gate: SourceSummaryGate?
  static var allowed: [Bool] = []

  static func reset() {
    calls = []
    outcome = .success(.init(markdown: "生成された要約"))
    gate = nil
    allowed = []
  }
  static func summarize(_ input: MeetingSummaryInput, engine: AIEngine, llm: LLMSelection,
                        authorize: (@MainActor () -> Bool)?,
                        progress: @escaping @MainActor (String) -> Void) async -> Result<MeetingSummary, AIAnswerFailure> {
    calls.append((input, engine, llm))
    if let gate { await gate.wait() }
    let permits = authorize?() ?? true
    allowed.append(permits)
    return permits ? outcome : .failure(.contextChanged)
  }
}

@MainActor final class SourceSummaryGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var hasEntered = false
  func wait() async {
    hasEntered = true
    await withCheckedContinuation { continuation = $0 }
  }
  func entered() async {
    for _ in 0..<10_000 { if hasEntered { return }; await Task.yield() }
    preconditionFailure("Summary did not reach fixture boundary")
  }
  func resume() { continuation?.resume(); continuation = nil }
}
