import Foundation
import SQLite3

@main
struct AudioImportChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: AudioInbox.directory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    for change in 0..<8 { try await race(root, change: change) }
    try await sqlFailureAndRetry(root)
    try await unreadableAndQueued(root)
    print("AudioImportChecks: passed (production importAudio/handle/Inbox queue, real file copy/cleanup, Meeting codec and SQLite reopen; 8 suspended-duration context races, deleted-project fallback, SQL failure/retry, unreadable Inbox retention and queued import; duration/media boundary and navigation/model state are fixtures, no microphone/AV playback/network)")
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
