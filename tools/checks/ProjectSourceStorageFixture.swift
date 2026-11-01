import Foundation

// Only state, persistence presentation and evidence invalidation are fixtures.
// Source storage/note operations, SQLite, file I/O and codecs are production code.
@MainActor
final class MemoraModel {
  var store: LocalStore
  var localStore: LocalStore { store }
  var storeURL: URL
  var projectSources: [ProjectSource] = [] { didSet { projectSourceIndex.invalidate() } }
  var projectSourceIndex = IdentifiableIndex<ProjectSource>()
  var projectSourceProcessingIDs: Set<UUID> = []
  var sourcePreparationJobs: [UUID: (id: UUID, task: Task<Void, Never>)] = [:]
  #if MEMORA_WEB_SOURCE_CHECKS
  var projectWebFetchJobs: [UUID: (id: UUID, task: Task<WebSourceFetcher.Result, Error>)] = [:]
  #endif
  #if MEMORA_SOURCE_IMPORT_CHECKS
  var preparedSourceIDs: [UUID] = []
  var preparationHook: ((UUID) async -> Void)?
  var audioImportCalls = 0
  var discardedSourceExtractions: [ProjectSource] = []
  func discardSourceExtraction(for source: ProjectSource) { discardedSourceExtractions.append(source) }
  #if MEMORA_PDF_PARTITION_CHECKS
  func performProjectSourcePreparation(_ id: UUID) async {
    preparedSourceIDs.append(id)
    await preparationHook?(id)
  }
  func recoverInterruptedProjectSources(includingPending: Bool = false) {}
  #else
  func prepareProjectSource(_ id: UUID) async {
    preparedSourceIDs.append(id)
    await preparationHook?(id)
  }
  @discardableResult
  func scheduleProjectSourcePreparation(_ id: UUID, after predecessor: Task<Void, Never>? = nil) -> Task<Void, Never>? {
    let attempt = UUID()
    let job = Task {
      await predecessor?.value
      await prepareProjectSource(id)
      if sourcePreparationJobs[id]?.id == attempt { sourcePreparationJobs.removeValue(forKey: id) }
    }
    sourcePreparationJobs[id] = (attempt, job)
    return job
  }
  #endif
  #if !MEMORA_AUDIO_IMPORT_CHECKS
  func importAudio(from url: URL, spaceID: UUID?, importContext: LocalImportContext?) async -> UUID? {
    audioImportCalls += 1
    return nil
  }
  #endif
  #endif
  var spaces: [MemoraSpace] = []
  #if MEMORA_SHARE_PDF_CHECKS
  var recentProjects: [MemoraSpace] { spaces }
  var recentProjectIDs: [UUID] = []
  var isImportingShareInbox = false
  var shareInboxFailure: String?
  var shareInboxRequests: [ShareInboxRequest] = []
  var shareInboxRejectedIDs: [UUID] = []
  #endif
  #if MEMORA_AUDIO_IMPORT_CHECKS
  var meetings: [Meeting] = []
  var tasks: [AudioImportTask] = []
  var isImporting = false
  var importProgress: Double?
  var importErrorMessage: String?
  var deletionFailureMessage: String?
  var projectFilingNotice: String?
  var openedMeetingID: UUID?
  var isRecording = false
  var isSavingCapture = false
  var recordingDraft: UUID?
  var isImportingShareInbox = false
  var isAIChatResponding = false
  var residentJobs: [UUID: Bool] = [:]
  var projectChatJobs: [UUID: Bool] = [:]
  var webResearchJobs: [UUID: Bool] = [:]
  var processing = AudioImportProcessing()
  var speakerAnalysisIDs: Set<UUID> = []
  var isEnrollingSpeaker = false
  var isEmpty = true
  var pendingImportURLs: [URL] = []
  var pendingInformationImportContexts: [URL: LocalImportContext] = [:]
  var visibleProjectID: UUID?
  var inFlightImportURLs: Set<URL> = []
  var pendingImportNotice: String?
  var pendingInboxCount: Int?
  var trashedRecords: [AudioImportTrashedRecord] = []
  var missingRecordNotice: MissingRecordNotice?
  var selectedTab = AudioImportDestination.library
  var librarySection = AudioImportSection.files
  var libraryPath: [AudioImportRoute] = []
  var isCapturePresented = false
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func noteRealSaveForSampleCleanup() {}
  func presentPendingSampleCleanupIfNeeded() {}
  func openSavedMeeting(_ id: UUID) { openedMeetingID = id }
  var transcriptionStarts: [UUID] = []
  func startTranscription(_ id: UUID, onDeviceOnly: Bool, automaticallySummarize: Bool) {
    precondition(onDeviceOnly && automaticallySummarize)
    transcriptionStarts.append(id)
  }
  func openExternalSourceCitation(_ url: URL) {}
  func openSystemDestination(_ link: MemoraAppLink) {}
  func openTask(_ id: UUID) {}
  func startCapture() async {}
  #endif
  var currentTeamID: String? {
    didSet { if oldValue != currentTeamID { aiWorkspaceGeneration = UUID() } }
  }
  var aiWorkspaceGeneration = UUID()
  var retainedOfficeFileReferences: Set<String> = []
  var isRestoring = false
  var isStoreProtected = false
  var invalidated: [ProjectCitation.Target] = []
  var persistenceFailureMessage: String?
  var failurePresentation = PersistenceFailurePresentation()
  enum StorageKey {
    static let projectSources = "memoraProjectSources"
    #if MEMORA_AUDIO_IMPORT_CHECKS
    static let meetings = "memoraAudioImportMeetings"
    #endif
  }

  init(storeURL: URL) throws {
    self.storeURL = storeURL
    store = LocalStore(fileURL: storeURL)
    try store.prepare()
  }

  func space(id: UUID) -> MemoraSpace? { spaces.first { $0.id == id } }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func invalidateProjectEvidence(_ targets: [ProjectCitation.Target]) { invalidated += targets }
  func handlingPersistenceFailureLocally<Value>(_ operation: () throws -> Value) rethrows -> Value {
    try failurePresentation.locallyHandled(operation)
  }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do {
      guard !isStoreProtected else { return false }
      try store.write(key, data: JSONEncoder().encode(value))
      return true
    } catch {
      if failurePresentation.shouldPresentGlobally { persistenceFailureMessage = "SQLite write failed" }
      return false
    }
  }

  func persistBatch(_ build: () throws -> [(key: String, data: Data)], removing: [String] = []) -> Bool {
    do {
      guard !isStoreProtected else { return false }
      try store.applyBatch(writes: try build(), removing: removing)
      return true
    } catch {
      if failurePresentation.shouldPresentGlobally { persistenceFailureMessage = "SQLite write failed" }
      return false
    }
  }
}
