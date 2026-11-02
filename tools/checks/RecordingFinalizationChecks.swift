import AVFoundation
import Foundation
import SQLite3

@main @MainActor
struct RecordingFinalizationChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    for duration: TimeInterval? in [0.25, 61, 86_400, nil, .nan, .infinity, 0, -1, Double(Int.max), .greatestFiniteMagnitude] {
      try await finalization(root, duration: duration)
    }
    for change in 0..<10 { try await suspendedInspection(root, change: change) }
    try await endActivityRace(root)
    for duration: TimeInterval? in [61, nil] { try await failedCommit(root, duration: duration) }
    try await retryWorkspaceRace(root)
    try await missingAudio(root)
    try await deletedProject(root)
    try await realAudioMetadata(root)
    try await finalizationMetrics(root)
    print("RecordingFinalizationChecks: PASS. Production stop/completion/retry with real SQLite and Meeting codecs; verified subsecond/24h metadata or unknown duration, no guessed clock/one-second fallback, marker/note/calendar retention, no inference on unreadable audio, 10 suspended races, live-activity race, duplicate-stop refusal, save rollback/retry/reopen, missing media and deleted project. Real WAV/container validation; microphone, Live Activity, duration scheduling, UI and inference are fixtures. No 24h recording/device quality claim.")
  }

  static func fixture(_ root: URL, _ name: String) throws -> (MemoraModel, URL, MemoraModel.RecordingDraft) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent(name + ".sqlite"))
    let audio = MediaFiles.directory.appendingPathComponent(name + ".m4a")
    try Data("PRESERVE ORIGINAL AUDIO BYTES".utf8).write(to: audio)
    let space = MemoraSpace(id: UUID(), name: "保存先", symbol: "folder")
    model.spaces = [space]
    let draft = MemoraModel.RecordingDraft(id: UUID(), fileName: audio.lastPathComponent,
      title: "停止時のタイトル", note: "本文と否定条件を保持する", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
      spaceID: space.id, markers: [RecordingMarker(timestamp: 0), RecordingMarker(timestamp: 30), RecordingMarker(timestamp: 80)])
    model.recordingDraft = draft
    model.persistRecordingDraft()
    model.recordingURL = audio
    model.recordingStartedAt = draft.startedAt
    model.recordingSpaceID = space.id
    model.recordingTitle = draft.title
    model.recordingNote = draft.note
    model.recordingMarkers = draft.markers!
    model.captureEvent = .init(id: "retained-calendar-id")
    model.isRecording = true
    return (model, audio, draft)
  }

  static func finalization(_ root: URL, duration: TimeInterval?) async throws {
    let (model, audio, draft) = try fixture(root, "finish-" + UUID().uuidString)
    let original = try Data(contentsOf: audio)
    MediaFiles.readDuration = { _ in duration }
    await model.stopCapture()
    precondition(!model.isSavingCapture && !model.isRecording && model.stops == 1)
    precondition(model.recordingDraft == nil && model.meetings.count == 1 && model.lifeLogEntries.count == 1)
    let record = model.meetings[0]
    precondition(record.id == draft.id && record.audioURL == audio && record.notes == draft.note)
    precondition(record.title == draft.title && record.calendarEventID == "retained-calendar-id" && record.spaceID == draft.spaceID)
    precondition(record.transcript.isEmpty && !record.privacy.allowsCloudAI)
    if let verified = RecordingAudioValidation.duration(duration) {
      precondition(record.duration == verified && record.status == .transcribing(0.12))
      precondition(record.recordingMarkers == RecordingMarker.validated(draft.markers!, duration: verified))
      precondition(model.processed == [record.id])
    } else {
      guard case .failed(let notice) = record.status else { preconditionFailure("Unreadable audio treated as ready") }
      precondition(record.duration == 0 && record.summary == notice && notice == RecordingAudioValidation.unreadableNotice)
      precondition(record.recordingMarkers == draft.markers && model.processed.isEmpty)
      precondition(!model.announcements.contains(where: { $0.contains("文字起こしを準備") }))
    }
    let reopened = LocalStore(fileURL: model.storeURL)
    try reopened.prepare()
    let saved: [Meeting] = try document(MemoraModel.StorageKey.meetings, store: reopened)!
    let entries: [LifeLogEntry] = try document(MemoraModel.StorageKey.lifeLogEntries, store: reopened)!
    var decodedExpected = record
    decodedExpected.rawAudioReference = audio.lastPathComponent
    precondition(saved == [decodedExpected] && entries == model.lifeLogEntries)
    guard case .missing = reopened.readOutcome(MemoraModel.StorageKey.recordingDraft) else { preconditionFailure("Draft not atomically removed") }
    expect(try Data(contentsOf: audio) == original)
    await model.stopCapture()
    precondition(model.meetings.count == 1 && model.stops == 1)
  }

  static func suspendedInspection(_ root: URL, change: Int) async throws {
    let (model, audio, draft) = try fixture(root, "finish-race-\(change)")
    let gate = RecordingRecoveryGate<TimeInterval?>()
    MediaFiles.readDuration = { _ in await gate.wait() }
    let operation = Task { await model.stopCapture() }
    await gate.entered()
    await model.stopCapture()
    precondition(model.stops == 1)
    switch change {
    case 0: model.aiWorkspaceGeneration = UUID()
    case 1: model.recordingDraft?.id = UUID()
    case 2: model.recordingDraft?.note = "変更後の下書きを保護"
    case 3: model.recordingURL = MediaFiles.directory.appendingPathComponent("replacement.m4a")
    case 4: model.isStoreProtected = true
    case 5: model.isRestoring = true
    case 6: operation.cancel()
    case 7:
      model.meetings = [Meeting(id: draft.id!, title: "先に保存された記録", createdAt: .now, duration: 4,
        source: .recording, status: .ready, summary: "保持する", keyPoints: [], decisions: [], openQuestions: [], transcript: [], spaceID: nil, audioURL: audio)]
    case 8:
      model.lifeLogEntries = [LifeLogEntry(id: draft.id!, createdAt: .now, title: "先の保存", summary: "保持する", source: .iphone)]
    default: model.isRecording = true
    }
    let expectedDraft = model.recordingDraft, records = model.meetings, entries = model.lifeLogEntries
    gate.resume(61)
    await operation.value
    precondition(!model.isSavingCapture && model.recordingDraft == expectedDraft)
    precondition(model.meetings == records && model.lifeLogEntries == entries && model.processed.isEmpty)
    guard case .data = model.store.readOutcome(MemoraModel.StorageKey.recordingDraft),
          case .missing = model.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Stale save reached SQLite") }
    precondition(FileManager.default.fileExists(atPath: audio.path))
  }

  static func endActivityRace(_ root: URL) async throws {
    let (model, _, draft) = try fixture(root, "activity-race")
    let gate = RecordingRecoveryGate<Bool>()
    model.beforeEndActivity = { _ = await gate.wait() }
    MediaFiles.readDuration = { _ in preconditionFailure("Obsolete capture inspected media") }
    let operation = Task { await model.stopCapture() }
    await gate.entered()
    model.aiWorkspaceGeneration = UUID()
    gate.resume(true)
    await operation.value
    precondition(model.recordingDraft == draft && model.meetings.isEmpty && model.processed.isEmpty && !model.isSavingCapture)
  }

  static func failedCommit(_ root: URL, duration: TimeInterval?) async throws {
    let (model, audio, draft) = try fixture(root, "failed-commit-" + UUID().uuidString)
    MediaFiles.readDuration = { _ in duration }
    try sql("CREATE TRIGGER reject_recording BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", url: model.storeURL)
    await model.stopCapture()
    precondition(model.hasUnsavedRecording && model.isUnsavedRecordingAlertPresented)
    precondition(model.recordingDraft == draft && model.meetings.count == 1 && model.lifeLogEntries.count == 1 && model.processed.isEmpty)
    guard case .data = model.store.readOutcome(MemoraModel.StorageKey.recordingDraft),
          case .missing = model.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Partial recording save") }
    try sql("DROP TRIGGER reject_recording;", url: model.storeURL)
    MediaFiles.readDuration = { _ in preconditionFailure("Retry re-inspected a settled recording") }
    await model.retrySavingRecording()
    precondition(!model.hasUnsavedRecording && model.recordingDraft == nil && model.stops == 1)
    precondition(model.processed.count == (duration == nil ? 0 : 1))
    let reopened = LocalStore(fileURL: model.storeURL)
    try reopened.prepare()
    let saved: [Meeting] = try document(MemoraModel.StorageKey.meetings, store: reopened)!
    var decodedExpected = model.meetings[0]
    decodedExpected.rawAudioReference = audio.lastPathComponent
    precondition(saved == [decodedExpected] && saved[0].audioURL == audio)
    await model.retrySavingRecording()
    precondition(model.meetings.count == 1 && model.processed.count == (duration == nil ? 0 : 1))
  }

  static func missingAudio(_ root: URL) async throws {
    let (model, audio, draft) = try fixture(root, "missing-at-stop")
    try FileManager.default.removeItem(at: audio)
    MediaFiles.readDuration = { _ in nil }
    await model.stopCapture()
    let record = model.meetings[0]
    precondition(record.duration == 0 && record.notes == draft.note && record.recordingMarkers == draft.markers)
    precondition(record.summary == RecordingAudioValidation.missingNotice && model.processed.isEmpty)
  }

  static func retryWorkspaceRace(_ root: URL) async throws {
    let (model, _, draft) = try fixture(root, "retry-workspace-race")
    MediaFiles.readDuration = { _ in 61 }
    try sql("CREATE TRIGGER reject_recording BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", url: model.storeURL)
    await model.stopCapture()
    try sql("DROP TRIGGER reject_recording;", url: model.storeURL)
    let gate = RecordingRecoveryGate<Bool>()
    model.beforeCommit = { _ = await gate.wait() }
    let operation = Task { await model.retrySavingRecording() }
    await gate.entered()
    model.aiWorkspaceGeneration = UUID()
    gate.resume(true)
    await operation.value
    precondition(model.recordingDraft == draft && model.hasUnsavedRecording && model.processed.isEmpty)
    precondition(!model.isSavingCapture)
    let saved: [Meeting] = try document(MemoraModel.StorageKey.meetings, store: model.store)!
    precondition(saved.count == 1 && saved[0].id == draft.id)
  }

  static func finalizationMetrics(_ root: URL) async throws {
    let previous = UserDefaults.standard.object(forKey: AudioProcessingDiagnostics.enabledKey)
    defer {
      if let previous { UserDefaults.standard.set(previous, forKey: AudioProcessingDiagnostics.enabledKey) }
      else { UserDefaults.standard.removeObject(forKey: AudioProcessingDiagnostics.enabledKey) }
      AudioProcessingDiagnostics.invalidateSessions()
    }
    AudioProcessingDiagnostics.invalidateSessions()
    await AudioDiagnosticArchive.shared.clear()
    UserDefaults.standard.set(true, forKey: AudioProcessingDiagnostics.enabledKey)
    for duration: TimeInterval? in [61, nil] {
      let (model, _, _) = try fixture(root, "private-metrics-" + UUID().uuidString)
      MediaFiles.readDuration = { _ in duration }
      await model.stopCapture()
      let outcome: AudioDiagnosticReport.Outcome = duration == nil ? .failed : .success
      var report: AudioDiagnosticReport?
      for _ in 0..<200 {
        report = await AudioDiagnosticArchive.shared.snapshot().first { $0.kind == .recordingFinalization && $0.outcome == outcome }
        if report != nil { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      guard let report else { preconditionFailure("Finalization metrics missing") }
      precondition(report.isValid && report.totals["verification"]?.calls == 1 && report.totals["persistence"]?.calls == 1)
      precondition(report.audioSeconds == duration && (report.overallRTF != nil) == (duration != nil))
    }
    let exported = await AudioDiagnosticArchive.shared.export()
    precondition(!exported.contains("private-metrics-") && !exported.contains("本文と否定条件") && !exported.contains("保存先"))
    let numeric = root.appendingPathComponent("finalization-metrics.json")
    try Data(exported.utf8).write(to: numeric)
  }

  static func deletedProject(_ root: URL) async throws {
    let (model, _, _) = try fixture(root, "deleted-project")
    MediaFiles.readDuration = { _ in
      await MainActor.run { model.spaces = [] }
      return 61
    }
    await model.stopCapture()
    precondition(model.meetings.count == 1 && model.meetings[0].spaceID == nil && model.projectFilingNotice != nil)
  }

  static func realAudioMetadata(_ root: URL) async throws {
    let url = root.appendingPathComponent("real.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_000)!
      buffer.frameLength = 4_000
      for index in 0..<4_000 { buffer.floatChannelData![0][index] = 0 }
      try file.write(from: buffer)
    }
    let original = try Data(contentsOf: url)
    expect(await RecordingAudioValidation.readDuration(of: url) == 0.25)
    let invalid = root.appendingPathComponent("invalid.m4a")
    try Data("INVALID AUDIO CONTAINER".utf8).write(to: invalid)
    expect(await RecordingAudioValidation.readDuration(of: invalid) == nil)
    let empty = root.appendingPathComponent("empty.m4a")
    try Data().write(to: empty)
    expect(await RecordingAudioValidation.readDuration(of: empty) == nil)
    let link = root.appendingPathComponent("symlink.wav")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    expect(await RecordingAudioValidation.readDuration(of: link) == nil)
    expect(await RecordingAudioValidation.readDuration(of: root) == nil)
    expect(await RecordingAudioValidation.readDuration(of: root.appendingPathComponent("absent.wav")) == nil)
    expect(try Data(contentsOf: url) == original)
  }

  static func document<T: Decodable>(_ key: String, store: LocalStore) throws -> T? {
    guard case .data(let bytes) = store.readOutcome(key) else { return nil }
    return try JSONDecoder().decode(T.self, from: bytes)
  }

  static func sql(_ statement: String, url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
  }

  static func expect(_ value: Bool) { precondition(value) }
}
