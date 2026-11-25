import Foundation
import SQLite3
import Synchronization

@main
struct LocalStoreChecks {
  static func main() throws {
    let scratch = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let directory = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("store.sqlite")
    // An existing schema and JSON document must load without migration.
    var external: OpaquePointer?
    precondition(sqlite3_open(url.path, &external) == SQLITE_OK)
    defer { sqlite3_close(external) }
    try execute(external, "CREATE TABLE documents (key TEXT PRIMARY KEY, data BLOB NOT NULL, updated_at REAL NOT NULL);")
    try execute(external, "INSERT INTO documents VALUES('legacy', X'7b226f6c64223a747275657d', 1);")
    let store = LocalStore(fileURL: url)
    try store.prepare()
    precondition(read(store, "legacy") == Data("{\"old\":true}".utf8))
    let checksEmptyBlobs = !CommandLine.arguments.contains("--historical-baseline")
    if checksEmptyBlobs {
      try store.write("empty", data: Data())
      precondition(read(store, "empty") == Data(), "An existing empty blob must remain distinct from a missing document")
    }
    try store.applyBatch(writes: [("record", Data("original".utf8)), ("draft", Data("draft".utf8))], removing: [])
    try execute(external, "CREATE TRIGGER fail_fixture BEFORE INSERT ON documents WHEN NEW.key = 'fail' BEGIN SELECT RAISE(ABORT, 'fixture'); END;")
    do {
      try store.applyBatch(writes: [("record", Data("changed".utf8)), ("fail", Data("fail".utf8))], removing: ["draft"])
      preconditionFailure("Failed transaction committed")
    } catch {}
    precondition(read(store, "record") == Data("original".utf8) && read(store, "draft") == Data("draft".utf8))
    // The same cached INSERT must be usable after a constraint failure/rollback.
    try store.applyBatch(writes: [("record", Data("first".utf8)), ("record", Data("second".utf8))], removing: ["draft"])
    precondition(read(store, "record") == Data("second".utf8))
    guard case .missing = store.readOutcome("draft") else { preconditionFailure("Removal did not commit") }
    for count in [100, 1_000] {
      let payload = Data(repeating: 65, count: 2_048)
      let documents = (0..<count).map { (key: "fixture-\($0)", data: payload) }
      var samples: [Double] = []
      for _ in 0..<21 {
        let start = ContinuousClock.now
        try store.writeBatch(documents)
        let d = start.duration(to: .now).components
        samples.append(Double(d.seconds) * 1_000 + Double(d.attoseconds) / 1e15)
      }
      samples.sort()
      print(String(format: "sqlite-batch,%d,median=%.3f,p95=%.3f,max=%.3f", count, samples[10], samples[19], samples[20]))
      precondition(read(store, "fixture-\(count - 1)") == payload)
    }
    let reopened = LocalStore(fileURL: url)
    try reopened.prepare()
    precondition(read(reopened, "record") == Data("second".utf8))
    if checksEmptyBlobs {
      precondition(read(reopened, "empty") == Data(), "An empty blob must persist across connections")
    }
    try store.remove("record")
    guard case .missing = reopened.readOutcome("record") else { preconditionFailure() }
    try store.applyBatch(writes: [], removing: [])
    let failures = Mutex(0)
    DispatchQueue.concurrentPerform(iterations: 50) { number in
      do { try store.write("concurrent-\(number)", data: Data("\(number)".utf8)) }
      catch { failures.withLock { $0 += 1 } }
    }
    precondition(failures.withLock { $0 } == 0)
    for number in 0..<50 { precondition(read(store, "concurrent-\(number)") == Data("\(number)".utf8)) }
    print("LocalStoreChecks: passed (legacy bytes, atomic rollback, statement reuse after failure, ordered duplicate keys, removals, reopen, concurrency)")
    if checksEmptyBlobs { print("LocalStoreChecks: empty BLOB round trip passed") }
  }

  static func read(_ store: LocalStore, _ key: String) -> Data? {
    guard case .data(let value) = store.readOutcome(key) else { return nil }
    return value
  }
  static func execute(_ db: OpaquePointer?, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw LocalStore.StoreError.statement(sqlite3_errcode(db)) }
  }
}
