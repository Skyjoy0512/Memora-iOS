import CryptoKit
import Foundation
import SQLite3

/// Page checkpoints are derived local records, never a copy of the original
/// PDF or a saved permission. They can be discarded without losing user data.
final class PDFCheckpointStore: @unchecked Sendable {
  static let shared = PDFCheckpointStore(directory: directory)
  static let maximumBytes = 64 * 1024 * 1024
  static let maximumDocuments = 12
  static let retention: TimeInterval = 7 * 24 * 60 * 60

  private let lock = NSLock()
  private var database: OpaquePointer?
  private var root: URL
  private var now: () -> Date
  private var sessions: [UUID: String] = [:]

  init(directory: URL, now: @escaping () -> Date = Date.init) {
    root = directory
    self.now = now
  }

  deinit { if let database { sqlite3_close(database) } }

  static var directory: URL {
    #if MEMORA_HOST_CHECKS
    return ProjectSourceFiles.directory.appendingPathComponent("PDFCheckpoints", isDirectory: true)
    #else
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Memora/PDFCheckpoints", isDirectory: true)
    #endif
  }

  static func key(fingerprint: String) -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "pdf-v1.\(version.majorVersion).\(version.minorVersion).\(Locale.current.identifier).\(fingerprint)"
  }

  func begin(fingerprint: String) -> UUID {
    lock.lock()
    defer { lock.unlock() }
    let session = UUID()
    sessions[session] = fingerprint
    return session
  }

  func finish(_ session: UUID) {
    lock.lock()
    defer { lock.unlock() }
    sessions.removeValue(forKey: session)
  }

  func isActive(_ session: UUID, fingerprint: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return sessions[session] == fingerprint
  }

  func load(fingerprint: String, pageCount: Int, session: UUID) -> [PDFPageCheckpoint] {
    lock.lock()
    defer { lock.unlock() }
    let key = Self.key(fingerprint: fingerprint)
    do {
      guard sessions[session] == fingerprint else { return [] }
      try prepare()
      try prune(reserving: 0, keeping: key)
      let document = try statement("SELECT page_count FROM documents WHERE key = ?;")
      bind(key, statement: document, index: 1)
      let status = sqlite3_step(document)
      let matches = status == SQLITE_ROW && Int(sqlite3_column_int64(document, 0)) == pageCount
      sqlite3_finalize(document)
      guard status == SQLITE_ROW || status == SQLITE_DONE else { throw StoreFailure.database }
      guard matches else { try remove(key); return [] }
      let query = try statement("SELECT page, data, checksum FROM pages WHERE document_key = ? ORDER BY page;")
      defer { sqlite3_finalize(query) }
      bind(key, statement: query, index: 1)
      var result: [PDFPageCheckpoint] = [], bytes = 0
      var step = sqlite3_step(query)
      while step == SQLITE_ROW {
        let page = Int(sqlite3_column_int64(query, 0))
        let size = Int(sqlite3_column_bytes(query, 1))
        guard page == result.count + 1, page <= 2_000, size > 0, size <= 9 * 1024 * 1024,
              let pointer = sqlite3_column_blob(query, 1), let checksum = sqlite3_column_text(query, 2) else {
          throw StoreFailure.corrupt
        }
        let data = Data(bytes: pointer, count: size)
        guard Self.digest(data) == String(cString: checksum) else { throw StoreFailure.corrupt }
        let checkpoint = try JSONDecoder().decode(PDFPageCheckpoint.self, from: data)
        guard checkpoint.page == page, checkpoint.isValid(for: pageCount) else { throw StoreFailure.corrupt }
        bytes += checkpoint.encodedBytes
        guard bytes <= 8 * 1024 * 1024 else { throw StoreFailure.corrupt }
        result.append(checkpoint)
        step = sqlite3_step(query)
      }
      guard step == SQLITE_DONE else { throw StoreFailure.database }
      try touch(key)
      return result
    } catch {
      try? remove(key)
      return []
    }
  }

  func save(_ page: PDFPageCheckpoint, fingerprint: String, pageCount: Int, session: UUID) {
    lock.lock()
    defer { lock.unlock() }
    do {
      guard sessions[session] == fingerprint else { return }
      guard page.page <= 2_000, page.isValid(for: pageCount) else { return }
      try prepare()
      let key = Self.key(fingerprint: fingerprint)
      let data = try JSONEncoder().encode(page)
      guard data.count <= 9 * 1024 * 1024 else { return }
      try prune(reserving: data.count, keeping: key)
      try execute("BEGIN IMMEDIATE;")
      do {
        let document = try statement("INSERT OR IGNORE INTO documents (key, fingerprint, page_count, created_at, accessed_at) VALUES (?, ?, ?, ?, ?);")
        bind(key, statement: document, index: 1)
        bind(fingerprint, statement: document, index: 2)
        sqlite3_bind_int64(document, 3, sqlite3_int64(pageCount))
        sqlite3_bind_double(document, 4, now().timeIntervalSince1970)
        sqlite3_bind_double(document, 5, now().timeIntervalSince1970)
        let inserted = sqlite3_step(document)
        sqlite3_finalize(document)
        guard inserted == SQLITE_DONE else { throw StoreFailure.database }
        let prefix = try statement("SELECT COALESCE(MAX(page), 0), COALESCE(SUM(output_bytes), 0) FROM pages WHERE document_key = ?;")
        bind(key, statement: prefix, index: 1)
        let prefixStatus = sqlite3_step(prefix)
        let lastPage = Int(sqlite3_column_int64(prefix, 0))
        let outputBytes = Int(sqlite3_column_int64(prefix, 1))
        sqlite3_finalize(prefix)
        guard prefixStatus == SQLITE_ROW, lastPage >= 0, lastPage < 2_000,
              lastPage + 1 == page.page, outputBytes >= 0, outputBytes <= 8 * 1024 * 1024,
              outputBytes + page.encodedBytes <= 8 * 1024 * 1024 else { throw StoreFailure.corrupt }
        let insert = try statement("INSERT INTO pages (document_key, page, data, checksum, output_bytes) VALUES (?, ?, ?, ?, ?);")
        bind(key, statement: insert, index: 1)
        sqlite3_bind_int64(insert, 2, sqlite3_int64(page.page))
        _ = data.withUnsafeBytes { sqlite3_bind_blob(insert, 3, $0.baseAddress, Int32(data.count), Self.transient) }
        bind(Self.digest(data), statement: insert, index: 4)
        sqlite3_bind_int64(insert, 5, sqlite3_int64(page.encodedBytes))
        let written = sqlite3_step(insert)
        sqlite3_finalize(insert)
        guard written == SQLITE_DONE else { throw StoreFailure.database }
        try touch(key)
        try execute("COMMIT;")
      } catch {
        try? execute("ROLLBACK;")
        throw error
      }
    } catch {
      // Checkpoint failures do not discard a page that was successfully read.
    }
  }

  func invalidate(fingerprints: Set<String>) {
    lock.lock()
    defer { lock.unlock() }
    let normalized = Set(fingerprints.map { $0.lowercased() })
    sessions = sessions.filter { !normalized.contains($0.value) }
    do {
      try prepare()
      for fingerprint in fingerprints {
        let removal = try statement("DELETE FROM documents WHERE fingerprint = ?;")
        bind(fingerprint.lowercased(), statement: removal, index: 1)
        let status = sqlite3_step(removal)
        sqlite3_finalize(removal)
        guard status == SQLITE_DONE else { throw StoreFailure.database }
      }
    } catch { destroy() }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    sessions = [:]
    do { try prepare(); try execute("DELETE FROM documents;") }
    catch { destroy() }
  }

  func clearStoredResults() {
    lock.lock()
    defer { lock.unlock() }
    do { try prepare(); try execute("DELETE FROM documents;") }
    catch { destroy() }
  }

  private func prepare() throws {
    guard database == nil else { return }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var excluded = root
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try excluded.setResourceValues(resources)
    var handle: OpaquePointer?
    let status = sqlite3_open_v2(root.appendingPathComponent("pages.sqlite").path, &handle,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard status == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw StoreFailure.database
    }
    database = handle
    do {
      sqlite3_busy_timeout(handle, 1000)
      try execute("PRAGMA journal_mode = DELETE;")
      try execute("PRAGMA secure_delete = ON;")
      try execute("PRAGMA foreign_keys = ON;")
      try execute("PRAGMA page_size = 4096;")
      try execute("PRAGMA max_page_count = 24576;")
      try execute("CREATE TABLE IF NOT EXISTS documents (key TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, page_count INTEGER NOT NULL, created_at REAL NOT NULL, accessed_at REAL NOT NULL);")
      try execute("CREATE TABLE IF NOT EXISTS pages (document_key TEXT NOT NULL REFERENCES documents(key) ON DELETE CASCADE, page INTEGER NOT NULL, data BLOB NOT NULL, checksum TEXT NOT NULL, output_bytes INTEGER NOT NULL, PRIMARY KEY(document_key, page));")
    } catch {
      sqlite3_close(handle)
      database = nil
      throw error
    }
  }

  private func prune(reserving bytes: Int, keeping key: String) throws {
    let query = try statement("SELECT d.key, d.created_at, COALESCE(SUM(LENGTH(p.data)), 0) FROM documents d LEFT JOIN pages p ON p.document_key = d.key GROUP BY d.key ORDER BY d.accessed_at ASC;")
    var records: [(key: String, bytes: Int, expired: Bool)] = []
    var status = sqlite3_step(query)
    while status == SQLITE_ROW {
      if let pointer = sqlite3_column_text(query, 0) {
        let age = now().timeIntervalSince1970 - sqlite3_column_double(query, 1)
        records.append((String(cString: pointer), Int(sqlite3_column_int64(query, 2)), age < 0 || age > Self.retention))
      }
      status = sqlite3_step(query)
    }
    sqlite3_finalize(query)
    guard status == SQLITE_DONE else { throw StoreFailure.database }
    var total = records.reduce(bytes) { $0 + $1.bytes }
    var count = records.count + (records.contains { $0.key == key } ? 0 : 1)
    for record in records where record.expired || (record.key != key && (total > Self.maximumBytes || count > Self.maximumDocuments)) {
      try remove(record.key)
      total -= record.bytes
      count -= 1
    }
  }

  private func touch(_ key: String) throws {
    let update = try statement("UPDATE documents SET accessed_at = ? WHERE key = ?;")
    defer { sqlite3_finalize(update) }
    sqlite3_bind_double(update, 1, now().timeIntervalSince1970)
    bind(key, statement: update, index: 2)
    guard sqlite3_step(update) == SQLITE_DONE else { throw StoreFailure.database }
  }

  private func remove(_ key: String) throws {
    guard database != nil else { return }
    let removal = try statement("DELETE FROM documents WHERE key = ?;")
    defer { sqlite3_finalize(removal) }
    bind(key, statement: removal, index: 1)
    guard sqlite3_step(removal) == SQLITE_DONE else { throw StoreFailure.database }
  }

  private func statement(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard let database, sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw StoreFailure.database }
    return statement
  }

  private func bind(_ value: String, statement: OpaquePointer, index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, Self.transient)
  }

  private func execute(_ sql: String) throws {
    guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StoreFailure.database }
  }

  private func destroy() {
    if let database { sqlite3_close(database); self.database = nil }
    try? FileManager.default.removeItem(at: root)
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private enum StoreFailure: Error { case database, corrupt }
}
