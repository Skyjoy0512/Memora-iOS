import Foundation
import SQLite3

@main
@MainActor
struct RecordingRecoveryChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    try legacyDraftCodec()
    for duration in [61.0, nil, .nan, .infinity, 0, -1, Double(Int.max), .greatestFiniteMagnitude] as [TimeInterval?] {
      try await outcome(root, duration: duration)
    }
    for change in 0..<11 { try await suspendedInspection(root, change: change) }
    try await duplicateAndCaptureAdmission(root)
    try await sqlFailure(root)
    try await missingAudio(root)
    try await existingRecord(root)
    let capture = try String(contentsOfFile: "App/MemoraModel+Capture.swift", encoding: .utf8)
    precondition(capture.contains("guard await resolvePendingRecordingBeforeCapture() else { return }"))
    precondition(capture.range(of: "resolvePendingRecordingBeforeCapture()")!.lowerBound
      < capture.range(of: "isPreparingCapture = true")!.lowerBound)
    print("RecordingRecoveryChecks: passed (production recovery/admission, real Meeting/Journal codecs and SQLite rollback/reopen, 8 duration states, 11 suspended races, duplicate recovery, blocked replacement during commit, missing audio and marker retention; media duration, capture/persistence service boundaries are fixtures; no inference/network)")
  }

  static func legacyDraftCodec() throws {
    let draft = MemoraModel.RecordingDraft(id: UUID(), fileName: "legacy.m4a", title: "以前の録音",
      note: "古いメモを残す", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
      markers: [RecordingMarker(timestamp: 12)])
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
    precondition(Set(object.keys).isSubset(of: ["id", "fileName", "title", "note", "startedAt", "spaceID", "markers"]))
    for key in ["id", "spaceID", "markers"] { object.removeValue(forKey: key) }
    let legacy = try JSONDecoder().decode(MemoraModel.RecordingDraft.self, from: JSONSerialization.data(withJSONObject: object))
    precondition(legacy.id == nil && legacy.markers == nil && legacy.spaceID == nil)
    precondition(legacy.fileName == draft.fileName && legacy.note == draft.note && legacy.startedAt == draft.startedAt)
  }

  static func fixture(_ root: URL, _ name: String) throws -> (MemoraModel, URL, MemoraModel.RecordingDraft) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent(name + ".sqlite"))
    let audio = MediaFiles.directory.appendingPathComponent(name + ".m4a")
    try Data("UNMODIFIED RECOVERY AUDIO FIXTURE".utf8).write(to: audio)
    let draft = MemoraModel.RecordingDraft(id: UUID(), fileName: audio.lastPathComponent,
      title: "中断した架空の録音", note: "SQLiteへ保持するノート", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
      markers: [RecordingMarker(timestamp: 0), RecordingMarker(timestamp: 30), RecordingMarker(timestamp: 80)])
    model.recordingDraft = draft
    model.persistRecordingDraft()
    return (model, audio, draft)
  }

  static func document<T: Decodable>(_ key: String, store: LocalStore, type: T.Type) throws -> T? {
    guard case .data(let data) = store.readOutcome(key) else { return nil }
    return try JSONDecoder().decode(T.self, from: data)
  }

  static func outcome(_ root: URL, duration: TimeInterval?) async throws {
    let (model, audio, draft) = try fixture(root, "duration-" + UUID().uuidString)
    let bytes = try Data(contentsOf: audio)
    MediaFiles.readDuration = { _ in duration }
    expect(await model.resolvePendingRecordingBeforeCapture())
    precondition(model.recordingDraft == nil && !model.isRecoveringRecordingDraft)
    precondition(model.meetings.count == 1 && model.lifeLogEntries.count == 1)
    let record = model.meetings[0]
    precondition(record.id == draft.id && record.audioURL == audio && record.notes == draft.note)
    precondition(record.transcript.isEmpty && !record.privacy.allowsCloudAI)
    let valid = duration.map { $0.isFinite && $0 > 0 && $0 < Double(Int.max) } ?? false
    if valid {
      precondition(record.status == .waitingForTranscription && record.duration == duration)
      precondition(record.recordingMarkers.count == 2)
    } else {
      guard case .failed(let notice) = record.status else { preconditionFailure("Unreadable recovery claims readiness") }
      precondition(notice.contains("音声の長さを確認できません") && notice.contains("元のファイルは変更していません"))
      precondition(record.duration == 0 && record.summary == notice)
      precondition(record.recordingMarkers == draft.markers)
      precondition(!model.lifeLogEntries[0].summary.contains("復旧しました"))
    }
    let reopened = LocalStore(fileURL: model.storeURL)
    try reopened.prepare()
    let saved = try document(MemoraModel.StorageKey.meetings, store: reopened, type: [Meeting].self)!
    precondition(saved.count == 1 && saved[0].recordingMarkers == record.recordingMarkers)
    precondition(saved[0].status == record.status && saved[0].duration == record.duration)
    precondition(saved[0].audioURL == audio && saved[0].notes == draft.note)
    guard case .missing = reopened.readOutcome(MemoraModel.StorageKey.recordingDraft) else { preconditionFailure() }
    expect(try Data(contentsOf: audio) == bytes)
    await model.recoverRecordingDraft()
    precondition(model.meetings.count == 1 && model.lifeLogEntries.count == 1)
  }

  static func suspendedInspection(_ root: URL, change: Int) async throws {
    let (model, audio, _) = try fixture(root, "inspection-\(change)")
    let originalBytes = try Data(contentsOf: audio)
    let gate = RecordingRecoveryGate<TimeInterval?>()
    MediaFiles.readDuration = { _ in await gate.wait() }
    let operation = Task { await model.recoverRecordingDraft() }
    await gate.entered()
    switch change {
    case 0: model.aiWorkspaceGeneration = UUID()
    case 1: model.recordingDraft?.id = UUID()
    case 2: model.recordingDraft?.note = "後から編集したdraft"
    case 3: model.isStoreProtected = true
    case 4: model.isRestoring = true
    case 5: model.isRecording = true
    case 6: model.isPreparingCapture = true
    case 7: model.isSavingCapture = true
    case 8: operation.cancel()
    case 9:
      model.meetings = [Meeting(id: model.recordingDraft!.id!, title: "先に保存された記録", createdAt: .now,
        duration: 4, source: .recording, status: .ready, summary: "先の保存を残す", keyPoints: [], decisions: [],
        openQuestions: [], transcript: [], spaceID: nil, audioURL: audio)]
    default:
      model.lifeLogEntries = [LifeLogEntry(id: model.recordingDraft!.id!, createdAt: .now,
        title: "先に保存したメモ", summary: "保持する", source: .iphone)]
    }
    let expectedDraft = model.recordingDraft
    let meetings = model.meetings, entries = model.lifeLogEntries
    gate.resume(61)
    await operation.value
    precondition(!model.isRecoveringRecordingDraft && model.recordingDraft == expectedDraft)
    precondition(model.meetings == meetings && model.lifeLogEntries == entries)
    guard case .data = model.store.readOutcome(MemoraModel.StorageKey.recordingDraft),
          case .missing = model.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Stale inspection wrote records") }
    expect(try Data(contentsOf: audio) == originalBytes)
  }

  static func duplicateAndCaptureAdmission(_ root: URL) async throws {
    let (model, _, draft) = try fixture(root, "admission")
    let inspection = RecordingRecoveryGate<TimeInterval?>()
    MediaFiles.readDuration = { _ in
      await MainActor.run { model.durationCalls += 1 }
      return await inspection.wait()
    }
    let recovery = Task { await model.recoverRecordingDraft() }
    await inspection.entered()
    await model.recoverRecordingDraft()
    expect(await !model.resolvePendingRecordingBeforeCapture())
    precondition(model.durationCalls == 1 && model.recordingDraft == draft && model.recordingErrorMessage != nil)
    let commit = RecordingRecoveryGate<Bool>()
    model.beforeCommit = { _ = await commit.wait() }
    inspection.resume(61)
    await commit.entered()
    expect(await !model.resolvePendingRecordingBeforeCapture())
    precondition(model.recordingDraft == draft && model.isRecoveringRecordingDraft)
    commit.resume(true)
    await recovery.value
    precondition(model.meetings.count == 1 && model.lifeLogEntries.count == 1 && model.recordingDraft == nil)
    expect(await model.resolvePendingRecordingBeforeCapture())
  }

  static func sqlFailure(_ root: URL) async throws {
    let (model, audio, draft) = try fixture(root, "sql-rollback")
    MediaFiles.readDuration = { _ in nil }
    try sql("CREATE TRIGGER reject_recovery BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", url: model.storeURL)
    expect(await !model.resolvePendingRecordingBeforeCapture())
    precondition(model.recordingDraft == draft && model.meetings.isEmpty && model.lifeLogEntries.isEmpty)
    guard case .data = model.store.readOutcome(MemoraModel.StorageKey.recordingDraft),
          case .missing = model.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure() }
    precondition(FileManager.default.fileExists(atPath: audio.path))
    try sql("DROP TRIGGER reject_recovery;", url: model.storeURL)
    expect(await model.resolvePendingRecordingBeforeCapture())
    precondition(model.meetings.count == 1 && model.recordingDraft == nil)
  }

  static func missingAudio(_ root: URL) async throws {
    let (model, audio, draft) = try fixture(root, "missing")
    try FileManager.default.removeItem(at: audio)
    MediaFiles.readDuration = { _ in preconditionFailure("Missing audio was inspected") }
    await model.recoverRecordingDraft()
    precondition(model.meetings.isEmpty && model.lifeLogEntries.count == 1)
    precondition(model.lifeLogEntries[0].id == draft.id && model.lifeLogEntries[0].summary == draft.note)
    precondition(model.recordingDraft == nil)
  }

  static func existingRecord(_ root: URL) async throws {
    let (model, _, draft) = try fixture(root, "existing")
    model.lifeLogEntries = [LifeLogEntry(id: draft.id!, createdAt: draft.startedAt, title: "保存済み", summary: "保持する", source: .iphone)]
    MediaFiles.readDuration = { _ in preconditionFailure("Already recovered audio was inspected") }
    await model.recoverRecordingDraft()
    precondition(model.lifeLogEntries.count == 1 && model.recordingDraft == nil)
  }

  static func sql(_ statement: String, url: URL) throws {
    var database: OpaquePointer?
    precondition(sqlite3_open(url.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    precondition(sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK)
  }

  static func expect(_ value: Bool) { precondition(value) }
}
