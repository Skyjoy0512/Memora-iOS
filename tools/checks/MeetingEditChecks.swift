import Foundation
import SQLite3
import Synchronization

// The production domain extension runs unchanged. Only the model container and
// unused meeting fields are fixtures; persistence uses an isolated real SQLite DB.
@MainActor
final class MemoraModel {
  var store: LocalStore
  var meetings: [Meeting] = []
  var meetingSearchTexts: [UUID: String] = [:]
  var isRestoring = false
  var isStoreProtected = false
  var currentTeamID: String?
  var aiWorkspaceGeneration = UUID()
  var persistenceFailureMessage: String?
  var failures = 0
  enum StorageKey { static let meetings = "memoraMeetings" }
  init(url: URL) throws { store = LocalStore(fileURL: url); try store.prepare() }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do { try store.write(key, data: JSONEncoder().encode(value)); return true }
    catch { failures += 1; return false }
  }
  func persistMeetings() { _ = persistNow(meetings, forKey: StorageKey.meetings) }
  func persistBatch(_ build: () throws -> [(key: String, data: Data)]) -> Bool {
    do { try store.applyBatch(writes: try build(), removing: []); return true }
    catch { failures += 1; return false }
  }
}

enum RecordStore {
  static let encodingGate = Mutex<(entered: DispatchSemaphore, resume: DispatchSemaphore)?>(nil)
  static let encodingCount = Mutex(0)
  static func encoded<T: Encodable>(_ value: T) throws -> Data {
    encodingCount.withLock { $0 += 1 }
    if let gate = encodingGate.withLock({ value in let gate = value; value = nil; return gate }) {
      gate.entered.signal(); gate.resume.wait()
    }
    return try JSONEncoder().encode(value)
  }
}

struct Meeting: Codable, Equatable {
  var id = UUID()
  var title = "検証用会議"
  var notes = "保存済みノート"
  var summary = "保存済み要約"
  var decisions = ["本番切替はしない"]
  var processingLabel = "未処理"
  var transcript: [TranscriptSegment]
}

@main
enum MeetingEditChecks {
  @MainActor
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-edit-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("records.sqlite")
    let model = try MemoraModel(url: url)
    let segment = TranscriptSegment(id: UUID(), speaker: "話者1", speakerIsCertain: false,
      timestamp: 37, text: "えーと、12万円ではなく10万円です。", endTime: 42, speakerID: "speaker-1")
    let record = Meeting(transcript: [segment])
    let other = Meeting(transcript: [segment])
    let initial = [record, other]
    func read() throws -> [Meeting] {
      guard case .data(let bytes) = model.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("No fixture data") }
      return try JSONDecoder().decode([Meeting].self, from: bytes)
    }
    var connection: OpaquePointer?
    precondition(sqlite3_open(url.path, &connection) == SQLITE_OK)
    defer { sqlite3_close(connection) }
    func execute(_ statement: String) { precondition(sqlite3_exec(connection, statement, nil, nil, nil) == SQLITE_OK) }
    let edits: [@MainActor () async -> Bool] = [
      { await model.updateTranscriptSegment(meetingID: record.id, segmentID: segment.id, text: "  訂正：承認されていません。  ") },
      { await model.updateMeetingSummary(record.id, summary: "変更した要約") },
      { await model.updateMeetingNotes(record.id, notes: "変更したノート") },
      { await model.renameSpeaker(meetingID: record.id, segmentID: segment.id, name: "確認済み話者", appliesToAllSegments: true) }
    ]
    for edit in edits {
      model.meetings = initial
      model.meetingSearchTexts = [record.id: "original cache", other.id: "other cache"]
      precondition(model.persistNow(initial, forKey: MemoraModel.StorageKey.meetings))
      execute("CREATE TRIGGER fail_edit BEFORE INSERT ON documents WHEN NEW.key='memoraMeetings' BEGIN SELECT RAISE(ABORT, 'isolated meeting edit failure'); END;")
      let rejected = await edit()
      precondition(!rejected && model.meetings == initial && model.meetingSearchTexts[record.id] == "original cache")
      let rejectedBytes = try read()
      precondition(rejectedBytes == initial)
      execute("DROP TRIGGER fail_edit;")
      let saved = await edit()
      precondition(saved && model.meetings != initial && model.meetingSearchTexts[record.id] == nil)
      precondition(model.meetingSearchTexts[other.id] == "other cache" && model.meetings[1] == other)
      let savedRecords = try read()
      precondition(savedRecords == model.meetings)
      let reopened = LocalStore(fileURL: url)
      try reopened.prepare()
      guard case .data(let bytes) = reopened.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("Reopen failed") }
      let reopenedRecords = try JSONDecoder().decode([Meeting].self, from: bytes)
      precondition(reopenedRecords == model.meetings)
    }
    model.meetings = initial
    let before = try read()
    for edit in edits {
      model.isRestoring = true
      let restoring = await edit(); precondition(!restoring && model.meetings == initial)
      model.isRestoring = false
      model.isStoreProtected = true
      let protected = await edit(); precondition(!protected && model.meetings == initial)
      model.isStoreProtected = false
      model.currentTeamID = "team"
      let team = await edit(); precondition(!team && model.meetings == initial)
      model.currentTeamID = nil
    }
    let missing = await model.updateTranscriptSegment(meetingID: record.id, segmentID: UUID(), text: "不明なセグメント")
    let unchanged = try read()
    precondition(!missing && model.meetings == initial && unchanged == before)
    let task = Task { @MainActor in
      await model.updateTranscriptSegment(meetingID: record.id, segmentID: segment.id, text: "キャンセル済み")
    }
    task.cancel()
    let cancelled = await task.value
    precondition(!cancelled && model.meetings == initial)
    let saved = await model.updateTranscriptSegment(meetingID: record.id, segmentID: segment.id, text: "  訂正：承認されていません。  ")
    precondition(saved)
    var expected = segment
    expected.text = "訂正：承認されていません。"
    precondition(model.meetings[0].transcript == [expected] && model.meetings[0].decisions == record.decisions)
    precondition(model.failures == 4)
    model.meetings = initial
    model.meetingSearchTexts = [record.id: "original cache"]
    precondition(model.persistNow(initial, forKey: MemoraModel.StorageKey.meetings))
    execute("CREATE TRIGGER fail_edit BEFORE INSERT ON documents WHEN NEW.key='memoraMeetings' BEGIN SELECT RAISE(ABORT, 'synchronous edit failure'); END;")
    precondition(!model.updateMeeting(record.id) { $0.title = "未保存の名前" })
    precondition(model.meetings == initial && model.meetingSearchTexts[record.id] == "original cache")
    let rejectedRename = try read()
    precondition(rejectedRename == initial)
    execute("DROP TRIGGER fail_edit;")
    for state in 0..<4 {
      model.isRestoring = state == 0
      model.isStoreProtected = state == 1
      model.currentTeamID = state == 2 ? "team" : nil
      let task = Task { @MainActor in model.updateMeeting(record.id) { $0.title = "拒否する名前" } }
      if state == 3 { task.cancel() }
      let accepted = await task.value
      precondition(!accepted && model.meetings == initial && model.meetingSearchTexts[record.id] == "original cache")
    }
    model.isRestoring = false
    model.isStoreProtected = false
    model.currentTeamID = nil
    precondition(model.updateMeeting(record.id) { $0.title = "保存した名前" })
    let renamed = try read()
    precondition(renamed == model.meetings && renamed[0].title == "保存した名前")
    print("Synchronous meeting edits: SQLite failure leaves model/cache/store unchanged; protected/team/restore/cancel guards and retry passed")
    let noOpTitle = model.meetings[0].title
    let beforeNoOp = RecordStore.encodingCount.withLock { $0 }
    let noOpStore = try read()
    model.meetingSearchTexts[record.id] = "preserve"
    precondition(model.updateMeeting(record.id) { $0.title = noOpTitle })
    let afterNoOpStore = try read()
    precondition(RecordStore.encodingCount.withLock { $0 } == beforeNoOp && afterNoOpStore == noOpStore)
    precondition(model.meetingSearchTexts[record.id] == "preserve")
    for state in 0..<11 {
      model.meetings = initial
      model.currentTeamID = nil
      model.isRestoring = false
      model.isStoreProtected = false
      model.persistenceFailureMessage = nil
      precondition(model.persistNow(initial, forKey: MemoraModel.StorageKey.meetings))
      let entered = DispatchSemaphore(value: 0)
      let resume = DispatchSemaphore(value: 0)
      RecordStore.encodingGate.withLock { $0 = (entered, resume) }
      let pending = Task { @MainActor in await model.updateMeetingNotes(record.id, notes: "古い候補") }
      let didEnter = await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
          continuation.resume(returning: entered.wait(timeout: .now() + 10) == .success)
        }
      }
      precondition(didEnter)
      switch state {
      case 0:
        model.meetings[1].notes = "並行した別の編集"
        precondition(model.persistNow(model.meetings, forKey: MemoraModel.StorageKey.meetings))
      case 1: model.currentTeamID = "other"
      case 2: model.aiWorkspaceGeneration = UUID()
      case 3: model.isRestoring = true
      case 4: model.isStoreProtected = true
      case 5: pending.cancel()
      case 6:
        model.meetings.removeFirst()
        precondition(model.persistNow(model.meetings, forKey: MemoraModel.StorageKey.meetings))
      case 7:
        model.meetings[0].notes = "同じ本文への別の編集"
        precondition(model.persistNow(model.meetings, forKey: MemoraModel.StorageKey.meetings))
      case 8:
        model.meetings[0].summary = "並行した要約の更新"
        precondition(model.persistNow(model.meetings, forKey: MemoraModel.StorageKey.meetings))
      case 9: model.updateMeetingTransiently(record.id) { $0.processingLabel = "処理中" }
      default:
        model.meetings[0].notes = "古い候補"
        precondition(model.persistNow(model.meetings, forKey: MemoraModel.StorageKey.meetings))
      }
      var expectedModel = model.meetings
      let expectedStore = try read()
      resume.signal()
      let stale = await pending.value
      RecordStore.encodingGate.withLock { $0 = nil }
      let persisted = try read()
      if [0, 8, 9, 10].contains(state) {
        expectedModel[0].notes = "古い候補"
        precondition(stale && model.meetings == expectedModel && persisted == expectedModel)
      } else {
        precondition(!stale && model.meetings == expectedModel && persisted == expectedStore)
      }
    }
    // A continuously changing collection must stop after three encodes, without
    // replaying the edit closure or committing its stale candidate.
    model.meetings = initial
    model.isRestoring = false; model.isStoreProtected = false; model.currentTeamID = nil
    precondition(model.persistNow(initial, forKey: MemoraModel.StorageKey.meetings))
    let gates = (0..<3).map { _ in (entered: DispatchSemaphore(value: 0), resume: DispatchSemaphore(value: 0)) }
    RecordStore.encodingGate.withLock { $0 = gates[0] }
    let encodesBefore = RecordStore.encodingCount.withLock { $0 }
    var mutationCalls = 0
    let busy = Task { @MainActor in
      await model.commitMeetingChange(record.id) { mutationCalls += 1; $0.notes = "混雑中の編集" }
    }
    for round in 0..<3 {
      let gate = gates[round]
      let arrived = await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: gate.entered.wait(timeout: .now() + 10) == .success) }
      }
      precondition(arrived)
      model.meetings[1].notes = "連続した更新\(round)"
      precondition(model.persistNow(model.meetings, forKey: MemoraModel.StorageKey.meetings))
      if round < 2 { RecordStore.encodingGate.withLock { $0 = gates[round + 1] } }
      gate.resume.signal()
    }
    let busySaved = await busy.value
    let afterBusy = try read()
    precondition(!busySaved && mutationCalls == 1 && RecordStore.encodingCount.withLock { $0 } - encodesBefore == 3)
    precondition(afterBusy == model.meetings && afterBusy[0].notes == record.notes && model.persistenceFailureMessage != nil)
    print("Busy collection check passed: exactly three encodes, one edit closure invocation, no stale write")
    print("Meeting edit checks passed: production transcript/summary/notes/speaker edits, SQLite ABORT + retry/reopen, unchanged publication/cache on failure, segment evidence, team/restore/protected/cancel guards")
    print("Suspended encoding checks passed: unrelated record/field/processing updates rebase, same-field conflict/team/workspace/restore/protected/cancel/deletion refuse stale writes, no-op skips encoding")
  }
}
