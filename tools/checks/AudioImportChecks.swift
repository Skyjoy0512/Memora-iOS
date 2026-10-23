import Foundation
import SQLite3

@main
struct AudioImportChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: AudioInbox.directory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    for change in 0..<8 { try await race(root, change: change) }
    for change in 0..<8 { try await pickerRace(root, change: change) }
    try await pickerSuccessAndMissingContext(root)
    try await sqlFailureAndRetry(root)
    try await unreadableAndQueued(root)
    try await restoreAdmission(root)
    try await restoreDuringImport(root)
    try await pickerAcrossRestore(root)
    let backup = try String(contentsOfFile: "App/MemoraModel+Backup.swift", encoding: .utf8)
    precondition(backup.components(separatedBy: "try beginBackupRestore()").count == 2)
    precondition(backup.contains("try beginBackupRestore()\n    defer { isRestoring = false }"))
    print("AudioImportChecks: passed (production picked-audio/importAudio/handle/Inbox queue/restore admission, real file copy/cleanup, Meeting codec and SQLite reopen; 16 import races, 16 restore busy states, team/protected/nonempty/cancel refusal, real suspended import excludes restore, picker remains invalid after restore flag clears; duration/media, backup error types, empty-state classification and navigation/model state are fixtures, no microphone/AV playback/network)")
  }

  static func incoming(_ name: String) throws -> URL {
    let url = AudioInbox.directory.appendingPathComponent(name + ".m4a")
    try Data("HOST AUDIO PAYLOAD".utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: url.path)
    return url
  }
  @MainActor static func fixture(_ root: URL, _ name: String) throws -> (MemoraModel, UUID) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent(name + ".sqlite"))
    let project = MemoraSpace(id: UUID(), name: "架空の音声保存先", symbol: "folder")
    model.spaces = [project]
    return (model, project.id)
  }

  @MainActor static func race(_ root: URL, change: Int) async throws {
    let (model, projectID) = try fixture(root, "audio-race-\(change)")
    let url = try incoming("race-\(change)")
    let before = try recordings()
    let gate = AudioDurationGate()
    MediaFiles.readDuration = { _ in await gate.wait() }
    let operation = Task { await model.importAudio(from: url, spaceID: projectID) }
    await gate.entered()
    switch change {
    case 0: model.currentTeamID = "other"
    case 1: model.currentTeamID = "other"; model.currentTeamID = nil
    case 2: model.isRestoring = true
    case 3: model.isStoreProtected = true
    case 4: model.spaces = []
    case 5: model.spaces[0].name = "変更された保存先"
    case 6: operation.cancel()
    default: model.aiWorkspaceGeneration = UUID()
    }
    gate.resume(1.25)
    let id = await operation.value
    if change == 4 {
      precondition(id != nil && model.meetings.count == 1 && model.meetings[0].spaceID == nil)
      precondition(model.projectFilingNotice != nil && model.openedMeetingID == id)
      expect(try reload(model) == model.meetings)
    } else {
      precondition(id == nil && model.meetings.isEmpty && model.openedMeetingID == nil && !model.isImporting)
      expect(try recordings() == before)
      guard case .missing = model.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Rejected audio persisted") }
    }
    expect(try Data(contentsOf: url) == Data("HOST AUDIO PAYLOAD".utf8))
  }

  @MainActor static func sqlFailureAndRetry(_ root: URL) async throws {
    let (model, _) = try fixture(root, "audio-sql")
    let url = try incoming("sql-failure")
    let before = try recordings()
    MediaFiles.readDuration = { _ in 1.25 }
    try sql("CREATE TRIGGER reject_audio BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'audio check'); END;", model.storeURL)
    await model.handle(url)
    precondition(model.meetings.isEmpty && model.importErrorMessage != nil && model.persistenceFailureMessage != nil)
    precondition(model.inFlightImportURLs.isEmpty && !model.isImporting)
    expect(try recordings() == before && Data(contentsOf: url) == Data("HOST AUDIO PAYLOAD".utf8))
    try sql("DROP TRIGGER reject_audio;", model.storeURL)
    await model.handle(url)
    precondition(model.meetings.count == 1 && model.openedMeetingID == model.meetings[0].id)
    precondition(model.meetings[0].duration == 1.25 && model.meetings[0].status == .waitingForTranscription)
    precondition(!FileManager.default.fileExists(atPath: url.path))
    expect(try reload(model) == model.meetings)
    expect(try Data(contentsOf: model.meetings[0].audioURL!) == Data("HOST AUDIO PAYLOAD".utf8))
  }

  @MainActor static func pickerRace(_ root: URL, change: Int) async throws {
    let (model, projectID) = try fixture(root, "picker-race-\(change)")
    let context = LocalImportContext(projectID: projectID, in: model)!
    let url = try incoming("picker-race-\(change)")
    let before = try recordings()
    MediaFiles.readDuration = { _ in preconditionFailure("Expired picker context reached media read") }
    let picker = AudioDurationGate()
    let operation = Task {
      _ = await picker.wait()
      return await model.importPickedAudio(from: url, context: context)
    }
    await picker.entered()
    switch change {
    case 0: model.currentTeamID = "other"
    case 1: model.currentTeamID = "other"; model.currentTeamID = nil
    case 2: model.isRestoring = true
    case 3: model.isStoreProtected = true
    case 4: model.spaces = []
    case 5: model.spaces[0].name = "選択待ち中に変更"
    case 6: operation.cancel()
    default: model.aiWorkspaceGeneration = UUID()
    }
    picker.resume(nil)
    expect(await operation.value == nil)
    precondition(model.meetings.isEmpty && model.openedMeetingID == nil && !model.isImporting)
    precondition(model.importErrorMessage != nil)
    expect(try recordings() == before && Data(contentsOf: url) == Data("HOST AUDIO PAYLOAD".utf8))
    guard case .missing = model.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Expired picker persisted audio") }
  }

  @MainActor static func pickerSuccessAndMissingContext(_ root: URL) async throws {
    let (model, projectID) = try fixture(root, "picker-save")
    let url = try incoming("picker-save")
    let before = try recordings()
    MediaFiles.readDuration = { _ in preconditionFailure("Missing picker context reached media read") }
    expect(await model.importPickedAudio(from: url, context: nil) == nil)
    expect(try recordings() == before)
    precondition(model.meetings.isEmpty && model.importErrorMessage != nil)
    MediaFiles.readDuration = { _ in 1.25 }
    let context = LocalImportContext(projectID: projectID, in: model)!
    let id = await model.importPickedAudio(from: url, context: context)
    precondition(id != nil && model.meetings.count == 1 && model.meetings[0].spaceID == projectID)
    precondition(model.openedMeetingID == id)
    expect(try reload(model) == model.meetings)
    let global = LocalImportContext(in: model)!
    let second = await model.importPickedAudio(from: url, context: global)
    precondition(second != nil && second != id && model.meetings.first?.spaceID == nil)
    expect(try reload(model) == model.meetings)
    expect(try Data(contentsOf: url) == Data("HOST AUDIO PAYLOAD".utf8))
  }

  @MainActor static func unreadableAndQueued(_ root: URL) async throws {
    let (model, _) = try fixture(root, "audio-unreadable")
    let unreadable = try incoming("unreadable")
    let before = try recordings()
    MediaFiles.readDuration = { _ in nil }
    await model.handle(unreadable)
    precondition(FileManager.default.fileExists(atPath: unreadable.path) && model.meetings.isEmpty)
    expect(try recordings() == before)
    let queued = try incoming("queued")
    model.isRecording = true
    await model.handle(queued)
    precondition(model.pendingImportURLs == [queued] && FileManager.default.fileExists(atPath: queued.path))
    model.isRecording = false
    await model.processPendingImports()
    precondition(model.pendingImportURLs.isEmpty && model.inFlightImportURLs.isEmpty)
    precondition(FileManager.default.fileExists(atPath: queued.path) && model.meetings.isEmpty)
    MediaFiles.readDuration = { _ in 1.25 }
    await model.importInboxAudio()
    precondition(!FileManager.default.fileExists(atPath: queued.path) && !FileManager.default.fileExists(atPath: unreadable.path))
    expect(try reload(model) == model.meetings)
  }

  @MainActor static func restoreAdmission(_ root: URL) async throws {
    for state in 0..<19 {
      let (model, _) = try fixture(root, "restore-admission-\(state)")
      model.spaces = []
      let id = UUID()
      switch state {
      case 0: model.isRecording = true
      case 1: model.isSavingCapture = true
      case 2: model.recordingDraft = id
      case 3: model.isRestoring = true
      case 4: model.isImportingShareInbox = true
      case 5: model.isAIChatResponding = true
      case 6: model.residentJobs[id] = true
      case 7: model.projectChatJobs[id] = true
      case 8: model.webResearchJobs[id] = true
      case 9: model.processing.activeIDs.insert(id)
      case 10: model.speakerAnalysisIDs.insert(id)
      case 11: model.isEnrollingSpeaker = true
      case 12: model.isImporting = true
      case 13: model.pendingImportURLs = [root.appendingPathComponent("not-read.wav")]
      case 14: model.inFlightImportURLs = [root.appendingPathComponent("not-read.wav")]
      case 15: model.projectSourceProcessingIDs.insert(id)
      case 16: model.currentTeamID = "unconfigured"
      case 17: model.isStoreProtected = true
      default: model.isEmpty = false
      }
      let generation = model.aiWorkspaceGeneration
      let restoring = model.isRestoring
      do { try model.beginBackupRestore(); preconditionFailure("Restore admitted busy data") }
      catch let error as BackupPackage.BackupError {
        let expected: BackupPackage.BackupError = state == 16 ? .personalWorkspaceRequired : state == 17 ? .storeProtected : state == 18 ? .notEmpty : .busy
        precondition(error == expected)
      }
      precondition(model.aiWorkspaceGeneration == generation && model.isRestoring == restoring)
      precondition(model.meetings.isEmpty)
    }
    let (model, _) = try fixture(root, "restore-cancel")
    model.spaces = []
    let generation = model.aiWorkspaceGeneration
    let gate = AudioDurationGate()
    let operation = Task {
      _ = await gate.wait()
      try model.beginBackupRestore()
    }
    await gate.entered(); operation.cancel(); gate.resume(nil)
    do { try await operation.value; preconditionFailure("Cancelled restore admitted") }
    catch is CancellationError {}
    precondition(!model.isRestoring && model.aiWorkspaceGeneration == generation)
  }

  @MainActor static func restoreDuringImport(_ root: URL) async throws {
    let (model, _) = try fixture(root, "restore-during-import")
    model.spaces = []
    let url = try incoming("restore-during-import")
    let generation = model.aiWorkspaceGeneration
    let gate = AudioDurationGate()
    MediaFiles.readDuration = { _ in await gate.wait() }
    let operation = Task { await model.importAudio(from: url) }
    await gate.entered()
    do { try model.beginBackupRestore(); preconditionFailure("Restore raced audio copy") }
    catch let error as BackupPackage.BackupError { precondition(error == .busy) }
    precondition(!model.isRestoring && model.aiWorkspaceGeneration == generation)
    gate.resume(1.25)
    expect(await operation.value != nil)
    expect(try reload(model) == model.meetings)
    expect(try Data(contentsOf: url) == Data("HOST AUDIO PAYLOAD".utf8))
  }

  @MainActor static func pickerAcrossRestore(_ root: URL) async throws {
    let (model, _) = try fixture(root, "picker-across-restore")
    model.spaces = []
    let url = try incoming("picker-across-restore")
    let old = LocalImportContext(in: model)!
    let generation = model.aiWorkspaceGeneration
    let before = try recordings()
    try model.beginBackupRestore()
    precondition(model.isRestoring && model.aiWorkspaceGeneration != generation)
    precondition(LocalImportContext(in: model) == nil && !old.isCurrent(in: model))
    do { try model.beginBackupRestore(); preconditionFailure("Second restore admitted") }
    catch let error as BackupPackage.BackupError { precondition(error == .busy) }
    // Models the restore defer on either success or failure. Package rollback
    // itself is covered separately by BackupRestoreChecks, not by this flag.
    model.isRestoring = false
    MediaFiles.readDuration = { _ in preconditionFailure("Pre-restore picker reached media read") }
    expect(await model.importPickedAudio(from: url, context: old) == nil)
    precondition(model.meetings.isEmpty)
    expect(try recordings() == before)
    MediaFiles.readDuration = { _ in 1.25 }
    expect(await model.importPickedAudio(from: url, context: LocalImportContext(in: model)) != nil)
    expect(try reload(model) == model.meetings)
  }

  static func expect(_ value: Bool, file: StaticString = #fileID, line: UInt = #line) { precondition(value, file: file, line: line) }
  static func recordings() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: MediaFiles.directory.path)) }
  @MainActor static func reload(_ model: MemoraModel) throws -> [Meeting] {
    let store = LocalStore(fileURL: model.storeURL)
    try store.prepare()
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Missing meetings") }
    var decoded = try JSONDecoder().decode([Meeting].self, from: data)
    for index in decoded.indices {
      // Decoding retains the raw audio reference for backup validation. It is
      // absent on a newly constructed Meeting and is not a content difference.
      precondition(decoded[index].rawAudioReference == decoded[index].audioURL?.lastPathComponent)
      decoded[index].rawAudioReference = nil
    }
    return decoded
  }
  static func sql(_ statement: String, _ url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
  }
}

@MainActor private final class AudioDurationGate {
  var continuation: CheckedContinuation<TimeInterval?, Never>?
  func wait() async -> TimeInterval? { await withCheckedContinuation { continuation = $0 } }
  func entered() async {
    for _ in 0..<10_000 { if continuation != nil { return }; await Task.yield() }
    preconditionFailure("Audio duration was not requested")
  }
  func resume(_ value: TimeInterval?) { continuation!.resume(returning: value); continuation = nil }
}
