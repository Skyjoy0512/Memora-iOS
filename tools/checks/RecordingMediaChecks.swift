import Foundation
import SQLite3

@main
struct RecordingMediaChecks {
  @MainActor
  static func main() async throws {
    MediaFiles.directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("audio")
    try FileManager.default.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    let storeURL = MediaFiles.directory.deletingLastPathComponent().appendingPathComponent("store.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    let original = try record("first")
    transcriptionInputChecks(original)
    var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
    legacyJSON.removeValue(forKey: "originalAudioFileNames")
    let legacy = try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
    precondition(legacy.originalAudioFileNames.isEmpty && legacy.audioURL == original.audioURL)
    legacyJSON["audioURL"] = MediaFiles.directory.appendingPathComponent("missing-legacy.m4a").path
    var missingLegacy = try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
    precondition(missingLegacy.audioURL == nil && missingLegacy.rawAudioReference != nil)
    let savedMissing = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(missingLegacy))
    precondition(savedMissing.rawAudioReference == missingLegacy.rawAudioReference)
    missingLegacy.removeAudioReferences()
    let erasedReferences = try JSONSerialization.jsonObject(with: JSONEncoder().encode(missingLegacy)) as! [String: Any]
    precondition(erasedReferences["audioURL"] == nil && erasedReferences["originalAudioFileNames"] == nil)
    let roundtrip = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(original))
    precondition(roundtrip.originalAudioFileNames == original.originalAudioFileNames)
    precondition(roundtrip.managedAudioFileNames.count == 3)
    model.meetings = [original]
    try model.seed()
    model.removeMeetingAudio(original.id)
    precondition(!model.meetings[0].hasAudioFiles && model.pendingMediaDeletions.count == 3)
    try assertFiles(original, exist: true)
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    let persisted: [Meeting] = try decode(reopened, "meetings")
    let queued: [MemoraModel.PendingMediaDeletion] = try decode(reopened, "pending")
    precondition(!persisted[0].hasAudioFiles && queued.count == 3)
    model.undoAction!.undo()
    precondition(model.meetings[0].originalAudioFileNames == original.originalAudioFileNames)
    precondition(model.pendingMediaDeletions.isEmpty)
    try assertFiles(original, exist: true)
    model.undoAction = nil

    // Reject the second document write: SQLite must roll back both documents.
    var db: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let rejectSQL = "CREATE TRIGGER reject_pending BEFORE INSERT ON documents WHEN NEW.key = 'pending' BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
    precondition(sqlite3_exec(db, rejectSQL, nil, nil, nil) == SQLITE_OK)
    model.removeMeetingAudio(original.id)
    precondition(model.meetings[0].hasAudioFiles && model.pendingMediaDeletions.isEmpty && model.undoAction == nil)
    let stillStored: [Meeting] = try decode(reopened, "meetings")
    precondition(stillStored[0].hasAudioFiles)
    try assertFiles(original, exist: true)
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_pending", nil, nil, nil) == SQLITE_OK)
    model.removeMeetingAudio(original.id)
    let retryUndo = model.undoAction!
    precondition(sqlite3_exec(db, rejectSQL, nil, nil, nil) == SQLITE_OK)
    retryUndo.undo()
    precondition(!model.meetings[0].hasAudioFiles && model.pendingMediaDeletions.count == 3)
    try assertFiles(original, exist: true)
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_pending", nil, nil, nil) == SQLITE_OK)
    retryUndo.undo()
    precondition(model.meetings[0].hasAudioFiles && model.pendingMediaDeletions.isEmpty)
    model.undoAction = nil

    // A different record's permanent deletion cannot settle this undo offer.
    model.removeMeetingAudio(original.id)
    let other = try record("other")
    model.trashedRecords = [.init(meeting: other, deletedAt: .now)]
    model.permanentlyDeleteTrashedRecord(other.id)
    try assertFiles(other, exist: false)
    try assertFiles(original, exist: true)
    precondition(model.pendingMediaDeletions.count == 3)
    precondition(model.deletionFailureMessage == nil, "An unrelated undo offer is not a deletion failure")
    model.trashedLifeLogEntries = [.init(entry: .init(photoFileName: nil), deletedAt: .now)]
    model.permanentlyDeleteTrashedLifeLogEntry(model.trashedLifeLogEntries[0].id)
    try assertFiles(original, exist: true)
    model.undoAction!.undo(); model.undoAction = nil

    // Shared originals, trashed records and an active draft retain ownership.
    var shared = try record("shared")
    shared.originalAudioFileNames.append(original.originalAudioFileNames[0])
    model.meetings.append(shared)
    model.removeMeetingAudio(original.id)
    model.recordingDraft = .init(fileName: original.originalAudioFileNames[1])
    model.undoAction!.finalize(); model.undoAction = nil
    precondition(!exists(original.audioURL!))
    precondition(exists(MediaFiles.resolve(original.originalAudioFileNames[0])!))
    precondition(exists(MediaFiles.resolve(original.originalAudioFileNames[1])!))
    precondition(model.pendingMediaDeletions.isEmpty)
    model.recordingDraft = nil
    model.trashedRecords = [.init(meeting: shared, deletedAt: .now)]
    model.meetings.removeAll { $0.id == shared.id }
    model.pendingMediaDeletions = model.pendingDeletions(for: shared, includingPhotos: false)
    model.retryPendingMediaDeletions()
    try assertFiles(shared, exist: true)

    // Bulk removal and undo retain all part references without reverting notes.
    let older = try record("older", date: .now.addingTimeInterval(-100 * 86_400))
    var older2 = try record("older2", date: older.createdAt)
    older2.audioURL = nil; older2.rawAudioReference = nil
    model.meetings = [older, older2]
    model.pendingMediaDeletions = []
    model.removeAudio(olderThanDays: 90)
    precondition(model.meetings.allSatisfy { !$0.hasAudioFiles })
    precondition(model.pendingMediaDeletions.count == 5)
    model.meetings[0].notes = "edited after removal"
    model.undoAction!.undo(); model.undoAction = nil
    precondition(model.meetings[0].notes == "edited after removal")
    precondition(model.meetings[1].originalAudioFileNames == older2.originalAudioFileNames)
    precondition(model.pendingMediaDeletions.isEmpty)
    model.removeAudio(olderThanDays: 90)
    model.undoAction!.finalize(); model.undoAction = nil
    try assertFiles(older, exist: false)
    try assertFiles(older2, exist: false)

    // A failed deletion stays in the old one-file journal format and retries.
    let blocked = try record("blocked")
    model.meetings = [blocked]
    model.removeMeetingAudio(blocked.id)
    MediaFiles.failDeletion = true
    model.undoAction!.finalize(); model.undoAction = nil
    precondition(model.pendingMediaDeletions.count == 3)
    try assertFiles(blocked, exist: true)
    model.isStoreProtected = true
    MediaFiles.failDeletion = false
    model.deleteMedia(audioURL: blocked.audioURL, photoNames: [])
    model.retryPendingMediaDeletions()
    try assertFiles(blocked, exist: true)
    model.isStoreProtected = false
    model.retryPendingMediaDeletions()
    precondition(model.pendingMediaDeletions.isEmpty)
    try assertFiles(blocked, exist: false)

    let waiting = try record("waiting")
    let expired = try record("expired")
    model.meetings = [waiting]
    model.removeMeetingAudio(waiting.id)
    model.trashedRecords = [.init(meeting: expired, deletedAt: .now.addingTimeInterval(-31 * 86_400))]
    model.purgeExpiredTrash()
    precondition(model.trashedRecords.isEmpty && model.pendingMediaDeletions.count == 3)
    try assertFiles(expired, exist: false)
    try assertFiles(waiting, exist: true)
    model.undoAction!.undo(); model.undoAction = nil

    let usage = AudioUsage(meetings: [older2, waiting])
    precondition(usage.largestFirst.count == 2 && usage.oldCount == 1)
    let expected = waiting.managedAudioURLs.reduce(Int64(0)) { $0 + StorageUsage.size(of: $1) }
    precondition(usage.largestFirst.first { $0.meeting.id == waiting.id }?.bytes == expected)

    let outside = MediaFiles.directory.deletingLastPathComponent().appendingPathComponent("outside.m4a")
    try Data([1]).write(to: outside)
    var unsafe = try record("unsafe")
    unsafe.originalAudioFileNames = ["../outside.m4a", outside.path, "part-link.m4a"]
    try FileManager.default.createSymbolicLink(at: MediaFiles.directory.appendingPathComponent("part-link.m4a"), withDestinationURL: outside)
    model.meetings = [unsafe]
    model.removeMeetingAudio(unsafe.id)
    model.undoAction!.finalize()
    precondition(exists(outside))
    try await discardChecks(model, storeURL: storeURL)
    print("PASS: production Meeting legacy/parts codec, actual managed paths, SQLite removal+undo atomicity and rollback/reopen, bulk originals, targeted permanent deletion, shared/draft/trash ownership, protected store, unsafe paths")
  }

  static func transcriptionInputChecks(_ original: Meeting) {
    precondition(original.hasTranscriptionAudio)
    var parts = original
    parts.audioURL = nil
    precondition(!parts.hasTranscriptionAudio && !parts.hasPlaybackAudio)
    parts.recordingAudioManifest = .init(recordingID: parts.id, sampleRate: 44_100, parts: [
      .init(fileName: parts.originalAudioFileNames[0], frameOffset: 0, frameCount: 44_100, state: .finalized),
      .init(fileName: parts.originalAudioFileNames[1], frameOffset: 44_100, frameCount: 44_100, state: .finalized)
    ])
    precondition(parts.hasTranscriptionAudio && parts.hasSameAudioInput(as: parts))
    precondition(parts.hasPlaybackAudio)
    guard let playbackInput = parts.audioPlaybackInput, case .parts(let playbackManifest, _) = playbackInput else {
      preconditionFailure("Missing playback manifest")
    }
    precondition(playbackManifest == parts.recordingAudioManifest)
    var changed = parts
    changed.notes = "Unrelated edit"
    precondition(changed.hasSameAudioInput(as: parts))
    changed.recordingAudioManifest!.parts[1].frameCount = 88_200
    precondition(!changed.hasSameAudioInput(as: parts))
    changed = parts
    changed.originalAudioFileNames.swapAt(0, 1)
    precondition(!changed.hasSameAudioInput(as: parts))
    changed = parts
    changed.audioURL = original.audioURL
    precondition(!changed.hasSameAudioInput(as: parts))
    changed = parts
    changed.recordingAudioManifest!.parts[1].state = .writing
    changed.recordingAudioManifest!.parts[1].frameCount = nil
    precondition(!changed.hasTranscriptionAudio && !changed.hasSameAudioInput(as: parts))
    precondition(!changed.hasPlaybackAudio)
    changed = parts
    changed.recordingAudioManifest!.recordingID = UUID()
    precondition(!changed.hasTranscriptionAudio)
    print("PASS: production transcription input eligibility, unsealed/foreign manifest refusal, stale audio metadata detection, unrelated notes retained")
  }

  @MainActor
  static func discardChecks(_ model: MemoraModel, storeURL: URL) async throws {
    let record = try record("discard")
    let manifest = RecordingAudioManifest(recordingID: record.id, sampleRate: 44_100, parts: [
      .init(fileName: record.originalAudioFileNames[0], frameOffset: 0, frameCount: 44_100, state: .finalized),
      .init(fileName: record.originalAudioFileNames[1], frameOffset: 44_100, frameCount: nil, state: .writing)
    ])
    model.meetings = []
    model.recordingDraft = .init(fileName: manifest.fileNames[1], audioManifest: manifest)
    model.recordingURL = MediaFiles.resolve(manifest.fileNames[1])
    model.isRecording = true
    model.isCapturePresented = true
    model.pendingMediaDeletions = []
    try model.store.write("draft", data: JSONEncoder().encode(model.recordingDraft))
    var db: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_discard BEFORE DELETE ON documents WHEN OLD.key = 'draft' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    await model.cancelCapture()
    precondition(model.recordingDraft?.audioManifest == manifest && model.pendingMediaDeletions.isEmpty)
    precondition(model.isCapturePresented && model.recordingErrorMessage != nil)
    for name in manifest.fileNames { precondition(exists(MediaFiles.resolve(name)!)) }
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_discard", nil, nil, nil) == SQLITE_OK)
    // Another record owns the first part; explicit discard removes only the other.
    var owner = record
    owner.audioURL = nil
    owner.originalAudioFileNames = [manifest.fileNames[0]]
    model.meetings = [owner]
    await model.cancelCapture()
    precondition(model.recordingDraft == nil && model.pendingMediaDeletions.isEmpty && !model.isCapturePresented)
    precondition(exists(MediaFiles.resolve(manifest.fileNames[0])!))
    precondition(!exists(MediaFiles.resolve(manifest.fileNames[1])!))
    guard case .missing = model.store.readOutcome("draft") else { preconditionFailure("Discard did not settle draft") }
  }

  static func record(_ prefix: String, date: Date = .now) throws -> Meeting {
    let names = (0..<3).map { "\(prefix)-\($0).m4a" }
    for name in names { try Data(name.utf8).write(to: MediaFiles.resolve(name)!) }
    var record = Meeting(id: UUID(), title: prefix, createdAt: date, duration: 1, source: .recording,
      status: .ready, summary: "keep summary", keyPoints: [], decisions: [], openQuestions: [], transcript: [], spaceID: nil,
      audioURL: MediaFiles.resolve(names[0]))
    record.originalAudioFileNames = [names[1], names[2], names[1]]
    return record
  }
  static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
  static func assertFiles(_ meeting: Meeting, exist: Bool) throws {
    for url in meeting.managedAudioURLs { precondition(exists(url) == exist, "Unexpected audio ownership") }
  }
  static func decode<T: Decodable>(_ store: LocalStore, _ key: String) throws -> T {
    guard case .data(let data) = store.readOutcome(key) else { preconditionFailure("Missing document") }
    return try JSONDecoder().decode(T.self, from: data)
  }
}

@MainActor
final class MemoraModel {
  var store: LocalStore
  var meetings: [Meeting] = []
  var trashedRecords: [TrashedRecord] = []
  var trashedLifeLogEntries: [TrashedLifeLogEntry] = []
  var pendingMediaDeletions: [PendingMediaDeletion] = []
  var recordingDraft: RecordingDraft?
  var isStoreProtected = false
  var isRestoring = false
  var currentTeamID: String?
  var meetingSearchTexts: [UUID: String] = [:]
  var persistenceFailureMessage: String?
  var deletionFailureMessage: String?
  var undoAction: UndoAction?
  var recordingURL: URL?
  var isRecording = false
  var isSavingCapture = false
  var hasUnsavedRecording = false
  var isPreparingCapture = false
  var isRecoveringRecordingDraft = false
  var isCapturePresented = false
  var captureEvent: String?
  var recordingErrorMessage: String?
  var recordingInterruptionMessage: String?
  struct RecordingDraft: Codable { var fileName: String; var audioManifest: RecordingAudioManifest? = nil }
  func stopRecorder() { isRecording = false }
  func resetRecordingClock() { recordingURL = nil }
  func endLiveActivity() async {}
  enum StorageKey {
    static let meetings = "meetings", pendingMediaDeletions = "pending", trash = "trash", lifeLogTrash = "journalTrash"
    static let recordingDraft = "draft"
  }
  init(storeURL: URL) throws {
    store = LocalStore(fileURL: storeURL); try store.prepare(); RecordStore.store = store
  }
  func seed() throws {
    try store.applyBatch(writes: [("meetings", try RecordStore.encoded(meetings)), ("pending", try RecordStore.encoded(pendingMediaDeletions))], removing: [])
  }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistBatch(_ build: () throws -> [(key: String, data: Data)], removing: [String] = []) -> Bool {
    guard !isStoreProtected else { return false }
    do { try store.applyBatch(writes: build(), removing: removing); return true } catch { persistenceFailureMessage = "save failed"; return false }
  }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    persistBatch { [(key, try RecordStore.encoded(value))] }
  }
  func persistPendingMediaDeletions() { _ = persistNow(pendingMediaDeletions, forKey: StorageKey.pendingMediaDeletions) }
  func scheduleUndo(_ action: UndoAction) { undoAction?.finalize(); undoAction = action }
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) -> Bool {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    var candidate = meetings
    change(&candidate[index])
    guard persistNow(candidate, forKey: StorageKey.meetings) else { return false }
    meetings = candidate
    return true
  }
}

enum MediaFiles {
  static var directory = FileManager.default.temporaryDirectory.appendingPathComponent("unused-fixture-root")
  static var failDeletion = false
  static func removeFixtureFile(at url: URL) throws {
    if failDeletion { throw CocoaError(.fileWriteNoPermission) }
    try FileManager.default.removeItem(at: url)
  }
  static func writePhoto(_ data: Data, thumbnailMaxSide: Int = 400) -> String? { nil }
  @discardableResult static func deletePhoto(_ name: String) -> Bool { true }
}
struct TemplateSummary: Hashable, Codable {}
enum SummaryPreviewCache { static func preview(for id: UUID, summary: String, build: (String) -> String) -> String { build(summary) } }
enum MarkdownBlockParser {
  static func hasBlockStructure(_ text: String) -> Bool { false }
  static func overview(of text: String) -> String { text }
}
struct TrashedRecord: Codable {
  var meeting: Meeting
  var deletedAt: Date
  var id: UUID { meeting.id }
  static let lifetime: TimeInterval = 30 * 86_400
}
struct FixtureJournalEntry: Codable { var id = UUID(); var photoFileName: String? }
struct TrashedLifeLogEntry: Codable {
  var entry: FixtureJournalEntry
  var deletedAt: Date
  var id: UUID { entry.id }
}
