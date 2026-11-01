import Foundation
import SQLite3
import CryptoKit

/// A discardable, device-local cache, separate from the backed-up user store.
/// SQLite bounds and serializes records; image bytes remain separate files.
/// Only SourceExtractionCache's actor accesses this instance.
final class SourceExtractionPersistence {
  static let maximumBytes = 32 * 1024 * 1024
  static let maximumEntryBytes = 12 * 1024 * 1024
  static let maximumEntries = 12
  static let retention: TimeInterval = 7 * 24 * 60 * 60

  private var database: OpaquePointer?
  private var root: URL
  private let now: () -> Date

  init(directory: URL, now: @escaping () -> Date = Date.init) {
    root = directory
    self.now = now
  }

  deinit { if let database { sqlite3_close(database) } }

  static var directory: URL {
    #if MEMORA_HOST_CHECKS
    return ProjectSourceFiles.directory.appendingPathComponent("ExtractionCache", isDirectory: true)
    #else
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Memora/SourceExtraction", isDirectory: true)
    #endif
  }

  func read(_ key: String) -> ProjectSourceExtractionResult? {
    do {
      try prepare()
      try prune()
      let query = try statement("SELECT data, data_hash FROM extractions WHERE key = ?;")
      defer { sqlite3_finalize(query) }
      bind(key, to: query, at: 1)
      guard sqlite3_step(query) == SQLITE_ROW,
            let bytes = sqlite3_column_blob(query, 0) else { return nil }
      let count = Int(sqlite3_column_bytes(query, 0))
      guard count > 0, count <= Self.maximumEntryBytes else { try remove(key); return nil }
      let data = Data(bytes: bytes, count: count)
      guard let storedHash = sqlite3_column_text(query, 1), digest(data) == String(cString: storedHash) else {
        try remove(key); return nil
      }
      let snapshot = try JSONDecoder().decode(SourceExtractionSnapshot.self, from: data)
      var thumbnail: Data?
      if let reference = snapshot.thumbnailReference {
        guard let url = ProjectSourceFiles.resolve(reference, in: root),
              try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
              try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= Self.maximumEntryBytes else {
          try remove(key); return nil
        }
        thumbnail = try Data(contentsOf: url)
        guard let thumbnail, snapshot.thumbnailFingerprint == digest(thumbnail) else { try remove(key); return nil }
      }
      guard let result = snapshot.result(thumbnail: thumbnail) else { try remove(key); return nil }
      let touch = try statement("UPDATE extractions SET accessed_at = ? WHERE key = ?;")
      defer { sqlite3_finalize(touch) }
      sqlite3_bind_double(touch, 1, now().timeIntervalSince1970)
      bind(key, to: touch, at: 2)
      try step(touch)
      return result
    } catch {
      try? remove(key)
      return nil
    }
  }

  func write(_ key: String, result: ProjectSourceExtractionResult) {
    var newThumbnail: URL?
    do {
      guard !result.blocks.isEmpty else { return }
      try prepare()
      let reference = result.thumbnail.map { _ in UUID().uuidString + ".thumb" }
      let snapshot = SourceExtractionSnapshot(result, thumbnailReference: reference,
        thumbnailFingerprint: result.thumbnail.map(digest))
      guard snapshot.result(thumbnail: result.thumbnail) != nil else { return }
      let data = try JSONEncoder().encode(snapshot)
      let bytes = data.count + (result.thumbnail?.count ?? 0)
      guard bytes <= Self.maximumEntryBytes else { return }
      try prune(reservingBytes: bytes, reservingEntry: true)
      if let reference, let thumbnail = result.thumbnail {
        let url = root.appendingPathComponent(reference)
        try thumbnail.write(to: url, options: .atomic)
        newThumbnail = url
      }
      // Replacements remove the previous thumbnail only after the new row lands.
      let previous = try thumbnailReference(for: key)
      let insert = try statement("INSERT OR REPLACE INTO extractions (key, data, bytes, created_at, accessed_at, thumbnail, data_hash) VALUES (?, ?, ?, ?, ?, ?, ?);")
      defer { sqlite3_finalize(insert) }
      bind(key, to: insert, at: 1)
      _ = data.withUnsafeBytes { sqlite3_bind_blob(insert, 2, $0.baseAddress, Int32(data.count), Self.transient) }
      sqlite3_bind_int64(insert, 3, sqlite3_int64(bytes))
      sqlite3_bind_double(insert, 4, now().timeIntervalSince1970)
      sqlite3_bind_double(insert, 5, now().timeIntervalSince1970)
      if let reference { bind(reference, to: insert, at: 6) } else { sqlite3_bind_null(insert, 6) }
      bind(digest(data), to: insert, at: 7)
      try step(insert)
      if let previous, let url = ProjectSourceFiles.resolve(previous, in: root) { try? FileManager.default.removeItem(at: url) }
    } catch {
      if let newThumbnail { try? FileManager.default.removeItem(at: newThumbnail) }
      // Saving a derived cache must never turn a successful import into failure.
    }
  }

  func clear() {
    do {
      try prepare()
      try execute("DELETE FROM extractions;")
      try removeOrphanThumbnails()
    } catch { destroy() }
  }

  func invalidate(fingerprints: Set<String>) {
    do {
      try prepare()
      for fingerprint in fingerprints {
        let query = try statement("SELECT key FROM extractions WHERE key LIKE ?;")
        bind("%.\(fingerprint).%", to: query, at: 1)
        var keys: [String] = []
        var status = sqlite3_step(query)
        while status == SQLITE_ROW {
          if let key = sqlite3_column_text(query, 0) { keys.append(String(cString: key)) }
          status = sqlite3_step(query)
        }
        sqlite3_finalize(query)
        guard status == SQLITE_DONE else { throw PersistenceFailure.database }
        for key in keys { try remove(key) }
      }
    } catch {
      // If selective deletion cannot finish, discard the derived store rather
      // than leave readable private text after its source has been removed.
      destroy()
    }
  }

  private func prepare() throws {
    guard database == nil else { return }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var excluded = root
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try excluded.setResourceValues(resources)
    var handle: OpaquePointer?
    let status = sqlite3_open_v2(root.appendingPathComponent("extractions.sqlite").path, &handle,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard status == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw PersistenceFailure.database
    }
    database = handle
    do {
      sqlite3_busy_timeout(handle, 1000)
      try execute("PRAGMA page_size = 4096;")
      try execute("PRAGMA journal_mode = DELETE;")
      try execute("PRAGMA secure_delete = ON;")
      // Freed SQLite pages are reused, and the database cannot grow without bound.
      try execute("PRAGMA max_page_count = 12288;")
      try execute("CREATE TABLE IF NOT EXISTS extractions (key TEXT PRIMARY KEY, data BLOB NOT NULL, bytes INTEGER NOT NULL, created_at REAL NOT NULL, accessed_at REAL NOT NULL, thumbnail TEXT, data_hash TEXT NOT NULL);")
      try prune()
      try removeOrphanThumbnails()
    } catch {
      sqlite3_close(handle)
      database = nil
      throw error
    }
  }

  private func prune(reservingBytes: Int = 0, reservingEntry: Bool = false) throws {
    let query = try statement("SELECT key, bytes, created_at FROM extractions ORDER BY accessed_at ASC;")
    var records: [(key: String, bytes: Int, expired: Bool)] = []
    var status = sqlite3_step(query)
    while status == SQLITE_ROW {
      if let key = sqlite3_column_text(query, 0) {
        let created = sqlite3_column_double(query, 2)
        let age = now().timeIntervalSince1970 - created
        records.append((String(cString: key), Int(sqlite3_column_int64(query, 1)), age > Self.retention || age < 0))
      }
      status = sqlite3_step(query)
    }
    sqlite3_finalize(query)
    guard status == SQLITE_DONE else { throw PersistenceFailure.database }
    var bytes = records.reduce(reservingBytes) { $0 + max(0, $1.bytes) }
    var count = records.count + (reservingEntry ? 1 : 0)
    for record in records where record.expired || bytes > Self.maximumBytes || count > Self.maximumEntries {
      try remove(record.key)
      bytes -= max(0, record.bytes)
      count -= 1
    }
  }

  private func thumbnailReference(for key: String) throws -> String? {
    let query = try statement("SELECT thumbnail FROM extractions WHERE key = ?;")
    defer { sqlite3_finalize(query) }
    bind(key, to: query, at: 1)
    guard sqlite3_step(query) == SQLITE_ROW, let text = sqlite3_column_text(query, 0) else { return nil }
    return String(cString: text)
  }

  private func remove(_ key: String) throws {
    guard database != nil else { return }
    let reference = try thumbnailReference(for: key)
    let removal = try statement("DELETE FROM extractions WHERE key = ?;")
    defer { sqlite3_finalize(removal) }
    bind(key, to: removal, at: 1)
    try step(removal)
    if let reference, let url = ProjectSourceFiles.resolve(reference, in: root) { try? FileManager.default.removeItem(at: url) }
  }

  private func removeOrphanThumbnails() throws {
    let query = try statement("SELECT thumbnail FROM extractions WHERE thumbnail IS NOT NULL;")
    var retained = Set<String>()
    var status = sqlite3_step(query)
    while status == SQLITE_ROW {
      if let value = sqlite3_column_text(query, 0) { retained.insert(String(cString: value)) }
      status = sqlite3_step(query)
    }
    sqlite3_finalize(query)
    guard status == SQLITE_DONE else { throw PersistenceFailure.database }
    for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      where url.pathExtension == "thumb" && !retained.contains(url.lastPathComponent) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func statement(_ sql: String) throws -> OpaquePointer {
    var value: OpaquePointer?
    guard let database, sqlite3_prepare_v2(database, sql, -1, &value, nil) == SQLITE_OK, let value else {
      throw PersistenceFailure.database
    }
    return value
  }

  private func execute(_ sql: String) throws {
    guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw PersistenceFailure.database }
  }

  private func step(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else { throw PersistenceFailure.database }
  }

  private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, Self.transient)
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func destroy() {
    if let database { sqlite3_close(database); self.database = nil }
    // This directory contains only disposable extraction records and thumbnails.
    try? FileManager.default.removeItem(at: root)
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private enum PersistenceFailure: Error { case database }
}
