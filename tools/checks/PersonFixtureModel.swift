import Foundation

// Production domain extensions and codecs are used unchanged. UI/notifications and
// legacy meeting/journal shapes are minimal fixtures; no app store or services are touched.
@MainActor final class MemoraModel {
  var store: LocalStore
  var fixtureStoreURL: URL
  var people: [Person] = [] { didSet { personIndex.invalidate() } }
  var tasks: [MemoraTask] = [] { didSet { taskIndex.invalidate() } }
  var meetings: [Meeting] = []
  var lifeLogEntries: [LifeLogEntry] = []
  var newestLifeLogEntries: [LifeLogEntry] { lifeLogEntries.sorted { $0.occurredAt > $1.occurredAt } }
  var trashedLifeLogEntries: [TrashedLifeLogEntry] = []
  var pendingMediaDeletions: [PendingMediaDeletion] = []
  var spaces: [FixtureSpace] = []
  var glossaryTerms: [String] = []
  var message = FixtureMessage()
  var personIndex = IdentifiableIndex<Person>()
  var taskIndex = IdentifiableIndex<MemoraTask>()
  var personMeetingCounts: [UUID: Int] { Dictionary(uniqueKeysWithValues: people.map { ($0.id, meetings(withPerson: $0.id).count) }) }
  var meetingsByPerson: [UUID: [Meeting]] { Dictionary(uniqueKeysWithValues: people.map { person in (person.id, meetings.filter { $0.participantIDs?.contains(person.id) == true }) }) }
  var aiPersonScopeID: UUID?
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  #if PERSON_PROVENANCE_CHECKS
  var calendarContextRevision = UUID()
  var agentBlockedExternalTools: [UUID: Set<String>] = [:]
  #if INTERFACE_TASK_EXECUTION_CHECKS
  var disabledIntegrationIDs: [String] = []
  var mcpPermissionRevision = UUID()
  var gmailPermissionRevision = UUID()
  var notionPermissionRevision = UUID()
  var activeMCPTools: [String: Bool] = [:]
  var isCalendarEnabled: Bool {
    get { integrationIsEnabled("calendar") }
    set { setIntegrationEnabled("calendar", enabled: newValue) }
  }
  #else
  var isCalendarEnabled = true
  func integrationIsEnabled(_ id: String) -> Bool { id != "calendar" || isCalendarEnabled }
  #endif
  #endif
  var isRestoring = false
  var isStoreProtected = false
  var rejectWrites = false
  var profile = FixtureProfile(name: "自分")
  var account: FixtureProfile?
  var deletionFailureMessage: String?
  var agentPluginPolicies: [UUID: AIPluginExecutionPolicy] = [:]
  var mcpResultsCurrent = true
  func mcpResultsAreCurrent(_ id: UUID) -> Bool { mcpResultsCurrent }
  var gmailResultsCurrent = true
  func gmailResultsAreCurrent(_ id: UUID) -> Bool { gmailResultsCurrent }
  #if ARTIFACT_PROVENANCE_CHECKS
  var documents: [MemoraDocument] = []
  var mailDrafts: [MailDraft] = []
  var projectSources: [ProjectSource] = []
  #if ASK_AI_SCENARIO_CHECKS
  var companyTemplates: [CompanyTemplate] = []
  #else
  var companyTemplates: [FixtureTemplateReference] = []
  #endif
  #if RESEARCH_PROJECT_STORAGE_CHECKS
  var webResearchReports: [WebResearchReport] = []
  var webResearchBusyIDs: Set<UUID> = []
  #endif
  var pendingMailDraft: MailDraft?
  var pendingSourceCitation: ArtifactSourceTarget?
  var missingRecordNotice: MissingRecordNotice?
  var hasMessage = true
  var approvalAction: (() async -> Void)?
  var approves = true
  var pluginPermitted = true
  #if INTELLIGENT_UI_CHECKS
  var isAIChatResponding = false
  var aiChatRequestID: UUID?
  var aiChatTask: Task<Void, Never>?
  var interfaceCalls: [AgentToolCall] = []
  #if INTERFACE_TASK_EXECUTION_CHECKS
  var pendingAgentApproval: AgentApproval?
  var agentApprovalWaiter = AgentInteractionWaiter<Bool>()
  var approvedAgentTaskDrafts: [UUID: [AgentTaskDraft]] = [:]
  #endif
  #endif
  #if CLOUD_SESSION_CHECKS
  var fixtureRegistry = AIToolRegistry()
  #endif
  #endif
  #if PERSON_PROVENANCE_CHECKS
  var isAIMemoryEnabled = true
  var aiMemories: [String] = []
  var aiMessages: [FixtureMessage] = []
  var reads: [RecordPrivacyTarget] { message.cloudProvenance?.references.map(\.target) ?? [] }
  #else
  var reads: [RecordPrivacyTarget] = []
  #endif
  enum StorageKey { static let tasks = "tasks", people = "people", meetings = "meetings", lifeLogEntries = "journal", lifeLogTrash = "journalTrash", pendingMediaDeletions = "deletions", autoLifeLogInbox = "inbox", documents = "documents", projectSources = "projectSources" }
  init(storeURL: URL) throws { fixtureStoreURL = storeURL; store = LocalStore(fileURL: storeURL); try store.prepare() }
  func isStoreWritable() -> Bool { !isRestoring && !isStoreProtected && !rejectWrites }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    guard isStoreWritable() else { return false }
    do { try store.write(key, data: RecordStore.encoded(value)); return true } catch { return false }
  }
  func persistBatch(_ build: () throws -> [(key: String, data: Data)], removing: [String] = []) -> Bool {
    guard isStoreWritable() else { return false }
    do { try store.applyBatch(writes: build(), removing: removing); return true } catch { return false }
  }
  func persistInBackground<T: Encodable>(_ value: T, forKey key: String) { _ = persistNow(value, forKey: key) }
  func persistMeetings() { _ = persistNow(meetings, forKey: StorageKey.meetings) }
  func persistTasks() { _ = persistNow(tasks, forKey: StorageKey.tasks) }
  func scheduleUndo(_ action: UndoAction) {}
  func tasks(forMeeting id: UUID) -> [MemoraTask] { tasks.filter { $0.meetingID == id } }
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  #if !PERSON_PROVENANCE_CHECKS
  func recordCloudReads(_ references: [RecordPrivacyTarget], messageID: UUID) { reads = references }
  func recordArtifactReads(_ references: [RecordPrivacyTarget], messageID: UUID) {}
  func markCloudProvenanceIncomplete(_ id: UUID) {}
  #endif
  func beginAgentStep(_ step: AgentStep, on id: UUID) -> UUID {
    #if INTERFACE_TASK_EXECUTION_CHECKS
    message.agentSteps.append(step)
    #endif
    return step.id
  }
  func finishAgentStep(_ id: UUID, on messageID: UUID, state: AgentStep.State, detail: String? = nil) {
    #if INTERFACE_TASK_EXECUTION_CHECKS
    guard let index = message.agentSteps.firstIndex(where: { $0.id == id }) else { return }
    message.agentSteps[index].state = state; message.agentSteps[index].detail = detail
    #endif
  }
  static func agentTaskLine(_ task: MemoraTask) -> String { "id=\(task.id) \(task.title) " + AnswerSourceCitation.marker(for: .record(.task(task.id))) }
  static func agentDate(_ date: Date) -> String { date.description }
}

#if ARTIFACT_PROVENANCE_CHECKS && !ASK_AI_SCENARIO_CHECKS
// Provenance-only checks need the file-ownership boundary, not an Office engine.
struct FixtureTemplateReference {
  var fileReference: String
}
#endif
struct Meeting: Identifiable, Hashable, Codable {
  var id = UUID(); var title: String; var participantIDs: [UUID]?; var privacy: RecordPrivacy
  var createdAt = Date.now; var spaceID: UUID?; var duration: Double = 0; var summary = ""; var keyPoints: [String] = []; var notes = ""; var transcript: [String] = []; var decisions: [String] = []; var openQuestions: [String] = []
  var minimumPrivacyClassification: RecordPrivacy.Classification { privacy.classification }; var shortSummaryPreview: String { title }; var displayTitle: String { title }; var summaryPreview: String { title }; var effectivePrivacy: RecordPrivacy { privacy }
}
struct FixtureProfile { var name: String; var displayName: String { name } }
@MainActor enum RecordStore {
  static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
  static func load(_ key: String) -> LocalStore.ReadOutcome { .missing }
}
@MainActor enum TaskReminderScheduler {
  #if INTERFACE_TASK_EXECUTION_CHECKS
  static var refreshed: [UUID] = []
  #endif
  static func refresh(_ task: MemoraTask) {
    #if INTERFACE_TASK_EXECUTION_CHECKS
    refreshed.append(task.id)
    #endif
  }
  static func cancel(taskID: UUID) {}
}
enum SummaryResponseParser { static func taskKey(_ value: String) -> String { value } }
#if !CLOUD_SESSION_CHECKS
enum AgentTool: String {
  case readPerson = "read_person", searchRecords = "search_records", readRecord = "read_record"
  case listProjects = "list_projects", listTasks = "list_tasks", reviewPeriod = "review_period"
  case fixtureUnsupported
  case draftEmail = "draft_email"
  case updateTasks = "update_tasks"
  var icon: MemoraIcon { .person2 }
}
extension AgentToolCall { var tool: AgentTool? { AgentTool(rawValue: name) } }
#endif
struct FixtureMessage {
  #if PERSON_PROVENANCE_CHECKS
  var id = UUID()
  var createdAt = Date.now
  var residentName: String?
  enum Role { case user, assistant }
  var role = Role.assistant
  var text = ""
  var isThinking = false
  #if INTELLIGENT_UI_CHECKS
  var finishedAt: Date?
  var documentIDs: [UUID] = []
  #if INTERFACE_TASK_EXECUTION_CHECKS
  var agentSteps: [AgentStep] = []
  var didChangeData = false
  var createdTaskIDs: [UUID] = []
  #endif
  #endif
  var cloudProvenance: AIConversationProvenance?
  var calendarReadSnapshot: AICalendarReadSnapshot?
  var cloudAuthorizationTargets: Set<RecordPrivacyTarget>?
  var projectSourceReferences: [AgentSourceReference] = []
  var sourceCitations: [ProjectCitation] = []
  var artifactProvenance: ArtifactProvenance?
  #endif
  var sources: [AIChatSource] = []; var interfaceTaskIDs: Set<UUID> = []; var interfaceProjectIDs: Set<UUID> = []; var interfaceWorkspaceID: String?
}
struct FixtureSpace { var id: UUID; var name: String }
struct JournalPlace { var latitude: Double; var longitude: Double }
enum TrashedRecord { static let lifetime: TimeInterval = 30 * 86_400 }
enum MediaFiles {
  static func writePhoto(_ data: Data, thumbnailMaxSide: Int? = nil) -> String? { nil }
  static func deletePhoto(_ name: String) -> Bool { true }
}
enum MeetingSummaryInput { static func line(for line: String) -> String { line } }
enum MemoraFormat { static func duration(_ value: TimeInterval) -> String { value.description } }
extension MemoraModel {
  struct PendingMediaDeletion: Codable { var id: UUID; var audioReference: String?; var photoNames: [String] }
  func retryPendingMediaDeletions(onlyIDs: Set<UUID>? = nil) {}
  func updateAgentMessage(_ id: UUID, change: (inout FixtureMessage) -> Void) { change(&message) }
  @discardableResult func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) -> Bool {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return false }; change(&meetings[index]); return true
  }
  func persistNowAsync<T: Encodable>(_ value: T, forKey key: String) async -> Bool { persistNow(value, forKey: key) }
  static func meetings(in scope: AIChatScope, from meetings: [Meeting]) -> [Meeting] {
    #if INTERFACE_TASK_EXECUTION_CHECKS
    return scope == .projects ? meetings.filter { $0.spaceID != nil } : meetings
    #else
    return meetings
    #endif
  }
  #if INTERFACE_TASK_EXECUTION_CHECKS
  static func tasks(in allowedMeetings: [Meeting], from tasks: [MemoraTask]) -> [MemoraTask] {
    let ids = Set(allowedMeetings.map(\.id))
    return tasks.filter { $0.meetingID.map(ids.contains) == true }
  }
  func toolRegistry() -> AIToolRegistry { fixtureRegistry }
  func stopAIChat() {
    aiChatRequestID = nil; aiChatTask?.cancel(); aiChatTask = nil
    agentApprovalWaiter.resolve(false)
    isAIChatResponding = false
  }
  #endif
  static func questionWords(in text: String) -> [String] { text.isEmpty ? [] : [text] }
  func searchText(for meeting: Meeting) -> String { meeting.title }
  func agentSourceMatches(query: String, messageID: UUID) -> [String] { [] }
}

#if PERSON_PROVENANCE_CHECKS
@MainActor enum CalendarService {
  enum Access { case granted, denied, unknown }
  static var access = Access.granted
  #if INTERFACE_TASK_EXECUTION_CHECKS
  static var observationStarts = 0
  static func beginAIObservation() { observationStarts += 1 }
  static var values: [FixtureCalendarEvent] = []
  static var reads = 0
  static var onRead: (() async -> Void)?
  static func events(on date: Date) async -> [FixtureCalendarEvent] {
    reads += 1; await onRead?(); return values
  }
  #else
  static func beginAIObservation() {}
  #endif
}
#if INTERFACE_TASK_EXECUTION_CHECKS
struct FixtureCalendarEvent {
  var id: String
  var title: String
  var start: Date
  var end: Date
  var isAllDay: Bool
}
#endif
// These unrelated retrieval domains stay empty; the authority logic is production code.
#if ARTIFACT_PROVENANCE_CHECKS
typealias AIChatMessage = FixtureMessage
enum DraftStore { static func clear(_ key: String) {} }
#if !ASK_AI_SCENARIO_CHECKS
struct ProjectSourceFiles { static let shared = ProjectSourceFiles(); func remove(_ names: [String]) async {} }
#endif
extension MemoraModel {
  var bottomContentClearance: Double { 0 }
  func space(id: UUID) -> FixtureSpace? { spaces.first { $0.id == id } }
  func source(id: UUID) -> ProjectSource? { projectSources.first { $0.id == id } }
  func canReadAgentSource(_ source: ProjectSource, compact: Bool, policy: AIPluginExecutionPolicy?) -> Bool {
    currentTeamID == nil && !isRestoring && !isStoreProtected && source.canProvideText
      && (source.projectID.map { space(id: $0) != nil } ?? true) && policy?.personID == nil
      && (compact || RecordAccessPolicy.allows(source.privacy, purpose: .cloudAI))
      && (policy == nil || policy?.limitsRecordReads == false)
  }
  enum FixtureEvidence { case document(UUID), source(UUID) }
  func invalidateProjectEvidence(_ evidence: [FixtureEvidence]) {}
  func noteProjectUsed(_ id: UUID) {}
  static let declinedOutcome = AgentToolOutcome(text: "declined")
  func pluginCallIsPermitted(_ call: AgentToolCall, messageID: UUID) -> Bool {
    #if CLOUD_SESSION_CHECKS
    return pluginPermitted && fixtureRegistry.permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID])
    #else
    return pluginPermitted
    #endif
  }
  func approve(tool: AgentTool, title: String, lines: [String], confirmTitle: String, messageID: UUID) async -> UUID? {
    await approvalAction?()
    return approves ? UUID() : nil
  }
}
#else
struct FixtureProjectSource: Codable { var id: UUID; var projectID: UUID? }
extension MemoraModel {
  func source(id: UUID) -> FixtureProjectSource? { nil }
  func canReadAgentSource(_ source: FixtureProjectSource, compact: Bool, policy: AIPluginExecutionPolicy?) -> Bool { false }
}
#endif
extension MemoraModel {
  func agentMessage(_ id: UUID) -> FixtureMessage? {
    #if INTELLIGENT_UI_CHECKS
    guard message.id == id else { return nil }
    #endif
    #if ARTIFACT_PROVENANCE_CHECKS
    guard hasMessage else { return nil }
    #endif
    return message
  }
  func relatedEpisodeContext(for text: String, budget: Int, cloud: Bool) -> (text: String, references: [AIRecordReference]) { ("", []) }
  static func trailingHistory(_ text: String, budget: Int) -> String { String(text.suffix(budget)) }
}
#endif

#if INTELLIGENT_UI_CHECKS
extension MemoraModel {
  // Capture the dispatch boundary; the existing task/registry runners verify
  // approval and writes. This fixture cannot change any task or call an API.
  func runAgentTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope, compact: Bool) async -> AgentToolOutcome {
    interfaceCalls.append(call)
    #if INTERFACE_TASK_EXECUTION_CHECKS
    // Registry assembly and the all-tool dispatcher are fixtures. The schema,
    // policy, approval waiter, task mutation and SQLite implementation are real.
    guard call.tool == .updateTasks, fixtureRegistry.permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID]) else {
      return AgentToolOutcome(text: "fixture dispatch rejected", isError: true)
    }
    return await updateTasksTool(call, messageID: messageID, scope: scope)
    #else
    return AgentToolOutcome(text: "fixture dispatch")
    #endif
  }
}
#endif
