import Foundation

@MainActor
final class MemoraModel {
  var store: LocalStore
  var storeURL: URL
  var recordingDraft: RecordingDraft?
  var isRecoveringRecordingDraft = false
  var isRecording = false
  var isPreparingCapture = false
  var isSavingCapture = false
  var isRestoring = false
  var isStoreProtected = false
  var recordingErrorMessage: String?
  var aiWorkspaceGeneration = UUID()
  var meetings: [Meeting] = []
  var lifeLogEntries: [LifeLogEntry] = []
  var spaces: [MemoraSpace] = []
  var beforeCommit: (() async -> Void)?
  var durationCalls = 0
  var performance = RecordingFinalizationPerformanceFixture()
  var recordingURL: URL?
  var recordingStartedAt: Date?
  var recordingSpaceID: UUID?
  var recordingTitle = ""
  var recordingNote = ""
  var recordingMarkers: [RecordingMarker] = []
  var captureEvent: RecordingFinalizationEventFixture?
  var persistenceFailureMessage: String?
  var hasUnsavedRecording = false
  var isUnsavedRecordingAlertPresented = false
  var pendingMeetingNavigationID: UUID?
  var isCapturePresented = true
  var recordingInterruptionMessage: String?
  var projectFilingNotice: String?
  var beforeEndActivity: (() async -> Void)?
  var stops = 0
  var processed: [UUID] = []
  var announcements: [String] = []

  func stopRecorder() { stops += 1; isRecording = false }
  func endLiveActivity() async { await beforeEndActivity?() }
  func noteRealSaveForSampleCleanup() {}
  func resetRecordingClock() { recordingURL = nil; recordingMarkers = []; recordingSpaceID = nil }
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func beginProcessing(_ id: UUID) { processed.append(id) }
  func announce(_ message: String) { announcements.append(message) }
  func processPendingImports() async {}

  enum StorageKey {
    static let recordingDraft = "memoraRecordingDraft"
    static let meetings = "memoraMeetings"
    static let lifeLogEntries = "memoraLifeLogEntries"
  }

  init(storeURL: URL) throws {
    self.storeURL = storeURL
    store = LocalStore(fileURL: storeURL)
    try store.prepare()
    RecordStore.store = store
  }

  func persistInBackground<T: Encodable>(_ value: T, forKey key: String) {
    try! store.write(key, data: RecordStore.encoded(value))
  }

  func persistBatchAsync(_ build: () throws -> [(key: String, data: Data)], removing: [String]) async -> Bool {
    guard !isStoreProtected else { return false }
    do {
      let writes = try build()
      await beforeCommit?()
      try store.applyBatch(writes: writes, removing: removing)
      return true
    } catch { return false }
  }

  // Memo insertion is a boundary fixture; separate Journal checks execute the
  // real editor. Its codec and the SQLite commit/removal here are real.
  func addLifeLogEntry(id: UUID, kind: LifeLogKind, title: String, summary: String, createdAt: Date,
                      photoData: Data?, eventDate: Date?, locationName: String?, removingDraft: String) -> Bool {
    let entry = LifeLogEntry(id: id, createdAt: createdAt, title: title, summary: summary,
      source: .iphone, meetingID: nil, kind: kind)
    let candidate = [entry] + lifeLogEntries
    do {
      try store.applyBatch(writes: [(StorageKey.lifeLogEntries, try RecordStore.encoded(candidate))], removing: [removingDraft])
      lifeLogEntries = candidate
      return true
    } catch { return false }
  }
}

struct RecordingFinalizationPerformanceFixture {
  func record(_ name: String, milliseconds: Double) {}
}

struct RecordingFinalizationEventFixture { var id: String }
