import Foundation

// OS scheduling, inference and the unused model fields are fixtures. Production
// queue/generation/ProcessingService/task extraction and real SQLite are linked.
@MainActor
final class MemoraModel {
  func summaryArtifactScope(ownerID: UUID, privacy: RecordPrivacy, llm: LLMSelection, projectID: UUID? = nil) -> SummaryArtifactScope? { nil }
  let store: LocalStore
  let processing = ProcessingService()
  let scheduler = FixtureSummaryScheduler()
  var summaryBackgroundScheduler: any SummaryBackgroundScheduling { scheduler }
  var summaryQueueRunID: UUID?
  var activeSummaryRuns: [UUID: UUID] = [:]
  var backgroundSummaryNotice: String?
  var pendingSummaryJobs: [PendingSummaryJob] = []
  var meetings: [Meeting] = []
  var tasks: [MemoraTask] = []
  var meetingSearchTexts: [UUID: String] = [:]
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var summaryConfigurationIdentity = [UUID()]
  var isRestoring = false
  var isStoreProtected = false
  var speakerAnalysisIDs: Set<UUID> = []
  var summaryPreferences = SummaryPreferences()
  var summaryModePreference = SummaryModePreference()
  let performance = FixturePerformance()
  var deliveries = 0
  var failures = 0
  enum StorageKey {
    static let meetings = "memoraMeetings"
    static let tasks = "memoraTasks"
    static let pendingSummaryJobs = "memoraPendingSummaryJobs"
  }
  let settingsAIConfiguration = (engine: AIEngine.cloud,
    llm: LLMSelection(provider: .openAI, modelID: "fixture-never-sent", displayName: "Fixture"))
  init(url: URL) throws { store = LocalStore(fileURL: url); try store.prepare() }
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  /// Voice analysis is a fixture here; ownership falls back to names.
  func speakerActionOwnership(owner: String?, title: String, in record: Meeting) -> ActionTaskOwner.Ownership? { nil }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do { try store.write(key, data: JSONEncoder().encode(value)); return true }
    catch { failures += 1; return false }
  }
  func persistBatch(meetings: [Meeting]? = nil, prepared: [UUID: Data] = [:],
                    _ build: () throws -> [(key: String, data: Data)]) -> Bool {
    do {
      var writes = try build()
      if let meetings { writes.append((key: "memoraMeetings", data: try RecordStore.encoded(meetings))) }
      try store.applyBatch(writes: writes, removing: [])
      return true
    } catch { failures += 1; return false }
  }
  @discardableResult
  func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) -> Bool {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    change(&meetings[index]); return persistNow(meetings, forKey: StorageKey.meetings)
  }
  func updateMeetingTransiently(_ id: UUID, change: (inout Meeting) -> Void) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
    change(&meetings[index])
  }
  func tasks(forMeeting id: UUID) -> [MemoraTask] { tasks.filter { $0.meetingID == id } }
  func insertTasks(_ additions: [MemoraTask]) -> Bool { tasks = additions + tasks; return true }
  func summaryChoice(_ id: String) -> SummaryTemplateChoice? { nil }
  func person(id: UUID) -> FixturePerson? { nil }
  func processingVocabulary(external: Bool) -> [String] { [] }
  func automaticSummaryCandidates(for meeting: Meeting, fallback: SummaryTemplateChoice) -> [SummaryTemplateChoice] { [fallback] }
  func automaticSummaryChoice(for meeting: Meeting, useCaseID: String?) -> SummaryTemplateChoice { .standard }
  func announce(_ text: String) {}
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    meeting(id: id).map { RecordAccessPolicy.allows($0.effectivePrivacy, purpose: purpose) } ?? false
  }
  func deliverSummaryToWebhooks(_ id: UUID) { deliveries += 1 }
  func runResidentsAfterMeeting(_ id: UUID) {}
  func offerPlusIfNeeded() {}
}

@MainActor
final class FixtureSummaryScheduler: SummaryBackgroundScheduling {
  var isForeground = true
  var starts: [UUID] = []
  var continuedRequests: [Bool] = []
  var expirations: [UUID: @MainActor () -> Void] = [:]
  var finishes: [(UUID, Bool)] = []
  var steps: [String] = []
  var failSubmission = false
  func scheduleDeferred(requiresNetwork: Bool?, onFailure: @escaping @MainActor (String) -> Void) {
    if failSubmission, requiresNetwork != nil { onFailure("fixture scheduling refused") }
  }
  func begin(jobID: UUID, requestsContinuedProcessing: Bool,
    onExpiration: @escaping @MainActor () -> Void, onFailure: @escaping @MainActor (String) -> Void) {
    starts.append(jobID); expirations[jobID] = onExpiration
    continuedRequests.append(requestsContinuedProcessing)
    if failSubmission { onFailure("fixture continued submission refused") }
  }
  func report(jobID: UUID, step: String) { steps.append(step) }
  func finish(jobID: UUID, success: Bool) {
    finishes.append((jobID, success))
  }
}

@MainActor
enum MeetingSummarizer {
  struct Request {
    var input: MeetingSummaryInput
    var engine: AIEngine
    var llm: LLMSelection
    var authorize: (@MainActor () -> Bool)?
    var progress: @MainActor (String) -> Void
    var complete: CheckedContinuation<Result<MeetingSummary, AIAnswerFailure>, Never>
  }
  static var requests: [Request] = []
  static func summarize(_ input: MeetingSummaryInput, engine: AIEngine, llm: LLMSelection,
    authorize: (@MainActor () -> Bool)? = nil,
    progress: @escaping @MainActor (String) -> Void) async -> Result<MeetingSummary, AIAnswerFailure> {
    if let authorize, !authorize() { return .failure(.cancelled) }
    return await withCheckedContinuation { requests.append(Request(input: input, engine: engine, llm: llm,
      authorize: authorize, progress: progress, complete: $0)) }
  }
}

enum AIEngineService { static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine } }
enum RecordStore { static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) } }
enum MemoraFormat { static func duration(_ value: Double) -> String { String(Int(value)) } }
struct FixturePerson { var name: String }
struct FixturePerformance { func record(_ name: String, milliseconds: Double) {} }
struct Meeting: Codable {
  var id = UUID()
  var title = "検証用・背景要約"
  var createdAt = Date(timeIntervalSince1970: 1_700_000_000)
  var duration: TimeInterval = 60
  var status: MeetingStatus = .waitingForSummary
  var summary = "保存済みの旧要約"
  var keyPoints: [String] = []
  var decisions: [String] = []
  var openQuestions: [String] = []
  var transcript = [TranscriptSegment(id: UUID(), speaker: "検証話者", speakerIsCertain: false,
    timestamp: 0, text: "承認前には公開しない。")]
  var privacy = RecordPrivacy()
  var derivedSensitivity: SummarySensitivity?
  var spaceID: UUID?
  var participantIDs: [UUID]?
  var summaryUseCaseID: String?
  var summaryVersions: [TemplateSummary] = []
  var activeSummaryVersionID: UUID?
  var displayTitle: String { title }
  var effectivePrivacy: RecordPrivacy {
    var effective = privacy
    if let derivedSensitivity { effective.protect(derivedSensitivity) }
    effective.updatedAt = privacy.updatedAt
    return effective
  }
}
struct TemplateSummary: Codable {
  var id = UUID()
  var markdown: String
  var keyPoints: [String] = []
  var decisions: [String] = []
  var openQuestions: [String] = []
  var generatedAt = Date.now
  var modeBreadcrumb: SummaryModeBreadcrumb? = nil
  var reconciledUserEdits: Bool?
  var knowledge: SummaryKnowledge?
  static func snapshot(record: Meeting, templateID: String?, preferences: SummaryPreferences,
    modelInfo: String, evidence: [GeneratedSummaryEvidence] = [], knowledge: SummaryKnowledge? = nil,
    reconciledUserEdits: Bool = false) -> Self {
      Self(markdown: record.summary, keyPoints: record.keyPoints, decisions: record.decisions, openQuestions: record.openQuestions, reconciledUserEdits: reconciledUserEdits, knowledge: knowledge)
    }
}
