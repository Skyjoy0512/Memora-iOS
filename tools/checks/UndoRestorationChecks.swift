import Foundation
import SQLite3

@main @MainActor
struct UndoRestorationChecks {
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    var cases = 0
    for kind in 0..<5 {
      let keys = kind == 0 ? ["tasks"] : kind <= 2 ? ["meetings", "tasks", "journal", "trash"] : ["journal", "journalTrash"]
      for key in keys {
        let model = try fixture(root)
        let initial = model.snapshot
        remove(kind, from: model)
        let deleted = model.snapshot
        let actionID = model.pendingUndo!.id
        try sql("CREATE TRIGGER reject_restore BEFORE INSERT ON documents WHEN NEW.key='\(key)' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", at: model.url)
        model.performPendingUndo()
        precondition(model.snapshot == deleted && model.pendingUndo?.id == actionID && model.undoDismissTask == nil)
        try stored(model, equals: deleted)
        precondition(model.failures == 1)
        try sql("DROP TRIGGER reject_restore;", at: model.url)
        model.performPendingUndo()
        precondition(model.pendingUndo == nil)
        precondition(model.meetings == initial.meetings && model.tasks == initial.tasks)
        precondition(Set(model.lifeLogEntries) == Set(initial.entries) && model.trashedRecords.isEmpty && model.trashedLifeLogEntries.isEmpty)
        try stored(model, equals: model.snapshot)
        let restored = model.snapshot
        model.performPendingUndo()
        precondition(model.snapshot == restored)
        cases += 1
      }
    }
    // Conflicts reject the entire batch, including records that could be restored.
    for kind in [0, 2, 4] {
      let model = try fixture(root)
      let deletedTask = model.tasks[2]
      remove(kind, from: model)
      if kind == 0 {
        var conflict = deletedTask; conflict.title = "既存の別内容"
        model.tasks.append(conflict)
      } else if kind == 2 {
        var conflict = model.trashedRecords[0].tasks[0]; conflict.title = "既存の別内容"
        model.tasks.append(conflict)
      } else {
        var conflict = model.trashedLifeLogEntries[0].entry; conflict.title = "既存の別内容"
        model.lifeLogEntries.append(conflict)
      }
      try model.seed()
      let before = model.snapshot
      model.performPendingUndo()
      precondition(model.pendingUndo != nil && model.snapshot == before && model.deletionFailureMessage != nil)
      try stored(model, equals: before)
      model.finalizePendingUndo()
    }
    for kind in 0..<5 {
      for state in 0..<3 {
        let model = try fixture(root); remove(kind, from: model)
        let before = model.snapshot; let actionID = model.pendingUndo!.id
        model.currentTeamID = state == 0 ? "team" : nil
        model.isRestoring = state == 1
        model.isStoreProtected = state == 2
        model.performPendingUndo()
        precondition(model.snapshot == before && model.pendingUndo?.id == actionID)
        try stored(model, equals: before)
        model.finalizePendingUndo()
      }
    }
    // A separately restored record is an idempotent success for the original offer.
    let manual = try fixture(root); remove(2, from: manual)
    let offer = manual.pendingUndo!
    precondition(manual.restoreTrashedRecords(Set(manual.trashedRecords.map(\.id)), preservingPosition: true))
    let beforeReplay = manual.snapshot
    precondition(offer.undo() && manual.snapshot == beforeReplay)
    manual.finalizePendingUndo()
    print("PASS production Undo: \(cases) real SQLite rollback/retry cases across task, single/batch meeting and single/batch journal; multi-document atomic restoration, positions, collision refusal, idempotence, retained offers and 15 read-only guards. Record shapes/reminder/processing/accessibility boundaries are fixtures, no user data or OS notifications.")
  }
  static func fixture(_ root: URL) throws -> MemoraModel {
    let model = try MemoraModel(url: root.appendingPathComponent(UUID().uuidString + ".sqlite"))
    model.meetings = (0..<3).map { Meeting(title: "会議\($0)", createdAt: Date(timeIntervalSince1970: Double(100 - $0))) }
    model.tasks = [2, 0, 1].map { MemoraTask(id: UUID(), title: "課題\($0)", meetingID: model.meetings[$0].id, isCompleted: false) }
    model.tasks.insert(MemoraTask(id: UUID(), title: "独立した課題", isCompleted: false), at: 1)
    model.lifeLogEntries = model.meetings.enumerated().map { LifeLogEntry(title: "日記\($0.offset)", meetingID: $0.element.id) }
    try model.seed()
    return model
  }
  static func remove(_ kind: Int, from model: MemoraModel) {
    switch kind {
    case 0: precondition(model.deleteTask(model.tasks[2].id))
    case 1: model.deleteMeeting(model.meetings[0].id)
    case 2: model.deleteMeetings([model.meetings[0].id, model.meetings[2].id])
    case 3: precondition(model.deleteLifeLogEntry(model.lifeLogEntries[0].id))
    default: precondition(model.deleteLifeLogEntries([model.lifeLogEntries[0].id, model.lifeLogEntries[2].id]))
    }
    precondition(model.pendingUndo != nil)
  }
  static func stored(_ model: MemoraModel, equals expected: Snapshot) throws {
    let reopened = LocalStore(fileURL: model.url); try reopened.prepare()
    func read<T: Decodable>(_ type: T.Type, _ key: String) throws -> T {
      guard case .data(let data) = reopened.readOutcome(key) else { preconditionFailure() }
      return try JSONDecoder().decode(type, from: data)
    }
    let actual = Snapshot(meetings: try read([Meeting].self, "meetings"), tasks: try read([MemoraTask].self, "tasks"),
      entries: try read([LifeLogEntry].self, "journal"), trash: try read([TrashedRecord].self, "trash"),
      journalTrash: try read([TrashedLifeLogEntry].self, "journalTrash"))
    precondition(actual == expected)
  }
  static func sql(_ sql: String, at url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
  }
}

struct Snapshot: Equatable { var meetings: [Meeting]; var tasks: [MemoraTask]; var entries: [LifeLogEntry]; var trash: [TrashedRecord]; var journalTrash: [TrashedLifeLogEntry] }
@MainActor final class MemoraModel {
  var url: URL; var store: LocalStore
  var meetings: [Meeting] = []; var tasks: [MemoraTask] = []; var lifeLogEntries: [LifeLogEntry] = []
  var trashedRecords: [TrashedRecord] = []; var trashedLifeLogEntries: [TrashedLifeLogEntry] = []
  var currentTeamID: String?; var isRestoring = false; var isStoreProtected = false
  var pendingUndo: UndoAction?; var undoDismissTask: Task<Void, Never>?
  var processing = Processing(); var deletionFailureMessage: String?; var failures = 0
  var snapshot: Snapshot { .init(meetings: meetings, tasks: tasks, entries: lifeLogEntries, trash: trashedRecords, journalTrash: trashedLifeLogEntries) }
  enum StorageKey { static let meetings = "meetings", tasks = "tasks", lifeLogEntries = "journal", trash = "trash", lifeLogTrash = "journalTrash" }
  init(url: URL) throws { self.url = url; store = LocalStore(fileURL: url); try store.prepare() }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool { persistBatch { [(key, try RecordStore.encoded(value))] } }
  func persistBatch(_ build: () throws -> [(key: String, data: Data)]) -> Bool {
    do { try store.applyBatch(writes: build(), removing: []); return true } catch { failures += 1; return false }
  }
  func seed() throws {
    try store.writeBatch([("meetings", RecordStore.encoded(meetings)), ("tasks", RecordStore.encoded(tasks)),
      ("journal", RecordStore.encoded(lifeLogEntries)), ("trash", RecordStore.encoded(trashedRecords)),
      ("journalTrash", RecordStore.encoded(trashedLifeLogEntries))])
  }
  func invalidateProjectEvidence(_ targets: [Target]) {}
  enum Target { case task(UUID), meeting(UUID) }
  struct Processing { func cancel(_ id: UUID) {} }
}
enum RecordStore { static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) } }
struct Meeting: Identifiable, Codable, Hashable { var id = UUID(); var title: String; var createdAt: Date; var displayTitle: String { title } }
struct LifeLogEntry: Identifiable, Codable, Hashable { var id = UUID(); var title: String; var meetingID: UUID? }
enum TaskReminderScheduler { static func cancel(taskID: UUID) {}; static func refresh(_ task: MemoraTask) {} }
enum UIAccessibility { static var isVoiceOverRunning: Bool { false }; static var isSwitchControlRunning: Bool { false } }
