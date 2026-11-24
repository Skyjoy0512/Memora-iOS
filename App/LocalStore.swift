import Foundation
import SQLite3

/// The app's structured data, kept in the system SQLite database inside the app
/// container. Settings stay in `UserDefaults`; media files live beside it.
///
/// Access is serialized with a lock rather than an actor: the model loads its
/// documents synchronously while it is created, and an actor would force that
/// load to become asynchronous with a loading state in every screen.
final class LocalStore {
  static let shared = LocalStore()

  enum StoreError: Error {
    case open(Int32)
    case statement(Int32)
    case filesystem
  }

  private let lock = NSLock()
  private var db: OpaquePointer?
  private var statements: [String: OpaquePointer] = [:]
  private let fileURL: URL

  init(fileURL: URL? = nil) {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    self.fileURL = fileURL ?? base
      .appendingPathComponent("Memora", isDirectory: true)
      .appendingPathComponent("memora.sqlite")
  }

  deinit {
    for statement in statements.values { sqlite3_finalize(statement) }
    if let db { sqlite3_close(db) }
  }

  /// Opens (and creates) the database. Safe to call more than once.
  func prepare() throws {
    lock.lock()
    defer { lock.unlock() }
    try protectFiles()
    guard db == nil else { return }

    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let status = sqlite3_open_v2(fileURL.path, &handle, flags, nil)
    guard status == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw StoreError.open(status)
    }
    db = handle

    do {
      try exec("PRAGMA journal_mode = WAL;")
      try exec("""
      CREATE TABLE IF NOT EXISTS documents (
        key TEXT PRIMARY KEY,
        data BLOB NOT NULL,
        updated_at REAL NOT NULL
      );
      """)
      try protectFiles()
    } catch {
      sqlite3_close(handle)
      db = nil
      throw error
    }
  }

  /// The database and its side files hold every record, so the folder that
  /// contains them stays complete-protected and out of device backups. Files
  /// that do not exist yet are fine: SQLite creates them on demand.
  private func protectFiles() throws {
    let manager = FileManager.default
    var folder = fileURL.deletingLastPathComponent()
    // Data protection is a device contract: on the Mac the same attribute
    // leaves the folder SQLite cannot open, which would break host test
    // harnesses. Backup exclusion applies everywhere.
    #if os(iOS)
    let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
    #else
    let protection: [FileAttributeKey: Any] = [:]
    #endif
    do {
      var isDirectory: ObjCBool = false
      if manager.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
        guard isDirectory.boolValue else { throw StoreError.filesystem }
      } else {
        try manager.createDirectory(
          at: folder,
          withIntermediateDirectories: true,
          attributes: protection.isEmpty ? nil : protection
        )
      }

      if !protection.isEmpty {
        try manager.setAttributes(protection, ofItemAtPath: folder.path)
      }

      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try folder.setResourceValues(values)

      guard !protection.isEmpty else { return }
      for path in [
        fileURL.path,
        fileURL.path + "-wal",
        fileURL.path + "-shm",
      ] where manager.fileExists(atPath: path) {
        try manager.setAttributes(protection, ofItemAtPath: path)
      }
    } catch let error as StoreError {
      throw error
    } catch {
      throw StoreError.filesystem
    }
  }

  /// What a read found: the document, nothing stored, or a store that could not
  /// answer. The three are kept apart because "nothing stored" may be a first
  /// run, while a failure must never be treated as one.
  enum ReadOutcome {
    case missing
    case data(Data)
    case failed
  }

  func readOutcome(_ key: String) -> ReadOutcome {
    lock.lock()
    defer { lock.unlock() }
    guard db != nil else { return .failed }

    let statement: OpaquePointer
    do { statement = try prepared("SELECT data FROM documents WHERE key = ?;") }
    catch { return .failed }
    defer { reset(statement) }

    sqlite3_bind_text(statement, 1, key, -1, Self.transient)
    switch sqlite3_step(statement) {
    case SQLITE_DONE:
      return .missing
    case SQLITE_ROW:
      let count = Int(sqlite3_column_bytes(statement, 0))
      guard let bytes = sqlite3_column_blob(statement, 0) else {
        // SQLite has no byte pointer for an existing empty blob. Calling it
        // missing can revive legacy data or overwrite a damaged document.
        return count == 0 && sqlite3_column_type(statement, 0) == SQLITE_BLOB
          ? .data(Data()) : .failed
      }
      return .data(Data(bytes: bytes, count: count))
    default:
      return .failed
    }
  }

  /// Detect both writes on this connection and changes committed by another
  /// process before reusing a bounded, derived in-memory document.
  var changeToken: String? {
    lock.lock()
    defer { lock.unlock() }
    guard let db, let statement = try? prepared("PRAGMA data_version;") else { return nil }
    defer { reset(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return "\(sqlite3_total_changes64(db)):\(sqlite3_column_int64(statement, 0))"
  }

  /// Replaces the document for `key` inside a transaction, so a failure leaves
  /// the previous version in place.
  func write(_ key: String, data: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    guard db != nil else { throw StoreError.open(0) }

    try exec("BEGIN IMMEDIATE;")
    do {
      try writeLocked(key, data: data)
      try exec("COMMIT;")
    } catch {
      try? exec("ROLLBACK;")
      throw error
    }
  }

  /// Writes several documents in one transaction, so an operation that spans
  /// more than one document (moving a record to the trash, say) lands completely
  /// or not at all.
  func writeBatch(_ documents: [(key: String, data: Data)]) throws {
    try applyBatch(writes: documents, removing: [])
  }

  /// Writes and removes documents in one transaction, so a commit that both
  /// stores a record and discards its draft cannot leave the two disagreeing.
  func applyBatch(writes: [(key: String, data: Data)], removing removals: [String]) throws {
    lock.lock()
    defer { lock.unlock() }
    guard db != nil else { throw StoreError.open(0) }
    guard !writes.isEmpty || !removals.isEmpty else { return }

    try exec("BEGIN IMMEDIATE;")
    do {
      for document in writes {
        try writeLocked(document.key, data: document.data)
      }
      for key in removals {
        try removeLocked(key)
      }
      try exec("COMMIT;")
    } catch {
      try? exec("ROLLBACK;")
      throw error
    }
  }

  /// One document write. The caller holds the lock and the transaction.
  private func writeLocked(_ key: String, data: Data) throws {
    guard let db else { throw StoreError.open(0) }

    let statement = try prepared("INSERT OR REPLACE INTO documents (key, data, updated_at) VALUES (?, ?, ?);")
    defer { reset(statement) }

    sqlite3_bind_text(statement, 1, key, -1, Self.transient)
    _ = data.withUnsafeBytes { buffer in
      sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), Self.transient)
    }
    sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StoreError.statement(sqlite3_errcode(db))
    }
  }

  func remove(_ key: String) throws {
    lock.lock()
    defer { lock.unlock() }
    guard db != nil else { throw StoreError.open(0) }
    try removeLocked(key)
  }

  /// One document removal. The caller holds the lock and the transaction.
  private func removeLocked(_ key: String) throws {
    guard let db else { throw StoreError.open(0) }

    let statement = try prepared("DELETE FROM documents WHERE key = ?;")
    defer { reset(statement) }
    sqlite3_bind_text(statement, 1, key, -1, Self.transient)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StoreError.statement(sqlite3_errcode(db))
    }
  }

  /// Every use is inside the existing lock, including reset and clearing bound
  /// blobs, so no active statement or bound payload escapes to another caller.
  private func prepared(_ sql: String) throws -> OpaquePointer {
    if let statement = statements[sql] { return statement }
    guard let db else { throw StoreError.open(0) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw StoreError.statement(sqlite3_errcode(db))
    }
    statements[sql] = statement
    return statement
  }

  private func reset(_ statement: OpaquePointer) {
    sqlite3_reset(statement)
    sqlite3_clear_bindings(statement)
  }

  private func exec(_ sql: String) throws {
    guard let db else { throw StoreError.open(0) }
    var error: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(db, sql, nil, nil, &error)
    if let error { sqlite3_free(error) }
    guard status == SQLITE_OK else { throw StoreError.statement(status) }
  }

  /// SQLite copies the bound value immediately.
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
