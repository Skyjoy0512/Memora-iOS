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
  }

  private let lock = NSLock()
  private var db: OpaquePointer?
  private let fileURL: URL

  private init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    fileURL = base
      .appendingPathComponent("Memora", isDirectory: true)
      .appendingPathComponent("memora.sqlite")
  }

  /// Opens (and creates) the database. Safe to call more than once.
  func prepare() throws {
    lock.lock()
    defer { lock.unlock() }
    guard db == nil else { return }

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let status = sqlite3_open_v2(fileURL.path, &handle, flags, nil)
    guard status == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw StoreError.open(status)
    }
    db = handle

    try exec("PRAGMA journal_mode = WAL;")
    try exec("""
      CREATE TABLE IF NOT EXISTS documents (
        key TEXT PRIMARY KEY,
        data BLOB NOT NULL,
        updated_at REAL NOT NULL
      );
      """)
  }

  func read(_ key: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    guard let db else { return nil }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT data FROM documents WHERE key = ?;", -1, &statement, nil) == SQLITE_OK else {
      return nil
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, key, -1, Self.transient)
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

    guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
    let count = Int(sqlite3_column_bytes(statement, 0))
    return Data(bytes: bytes, count: count)
  }

  /// Replaces the document for `key` inside a transaction, so a failure leaves
  /// the previous version in place.
  func write(_ key: String, data: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    guard let db else { throw StoreError.open(0) }

    try exec("BEGIN IMMEDIATE;")
    do {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(
        db,
        "INSERT OR REPLACE INTO documents (key, data, updated_at) VALUES (?, ?, ?);",
        -1,
        &statement,
        nil
      ) == SQLITE_OK else {
        throw StoreError.statement(sqlite3_errcode(db))
      }
      defer { sqlite3_finalize(statement) }

      sqlite3_bind_text(statement, 1, key, -1, Self.transient)
      _ = data.withUnsafeBytes { buffer in
        sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), Self.transient)
      }
      sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)

      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw StoreError.statement(sqlite3_errcode(db))
      }
      try exec("COMMIT;")
    } catch {
      try? exec("ROLLBACK;")
      throw error
    }
  }

  func remove(_ key: String) throws {
    lock.lock()
    defer { lock.unlock() }
    guard let db else { throw StoreError.open(0) }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "DELETE FROM documents WHERE key = ?;", -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.statement(sqlite3_errcode(db))
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, key, -1, Self.transient)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StoreError.statement(sqlite3_errcode(db))
    }
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
