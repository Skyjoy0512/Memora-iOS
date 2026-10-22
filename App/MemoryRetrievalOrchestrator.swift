import Foundation
import SQLite3
import Synchronization

/// Callers still supply currently authorized candidates on every lookup. An index
/// is reusable only for that exact ordered snapshot, never just its identifiers.
enum MemoryRetrievalOrchestrator {
  struct Hit {
    var item: MemoryRetrievalItem
    var relevance: Double
  }
  enum Failure: Error { case database }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private static let cache = Mutex(Cache())
  private static let clock = ContinuousClock()
  private static let retainedBudget = 16 * 1_024 * 1_024
  private static let textBudget = 2 * 1_024 * 1_024

  // Every SQLite operation, including destruction, stays inside the same lock.
  // The two slots let semantic and episode lookups alternate without rebuilding.
  private struct Cache {
    var workspaceID: String?
    var personID: UUID?
    var indexes: [Index] = []
#if MEMORA_HOST_CHECKS
    var builds = 0
    var reuses = 0
#endif
  }

  private final class Index: @unchecked Sendable {
    var items: [MemoryRetrievalItem]
    var kinds: Set<MemoryRetrievalItem.Kind>
    var lastUsed: ContinuousClock.Instant
    var estimatedBytes: Int
    private var db: OpaquePointer

    init(items: [MemoryRetrievalItem], textBytes: Int) throws {
      var connection: OpaquePointer?
      guard sqlite3_open_v2(":memory:", &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
            let connection else {
        if let connection { sqlite3_close(connection) }
        throw Failure.database
      }
      var completed = false
      defer { if !completed { sqlite3_close(connection) } }
      guard sqlite3_exec(connection, "CREATE VIRTUAL TABLE memory USING fts5(tokens); BEGIN;", nil, nil, nil) == SQLITE_OK else { throw Failure.database }
      var insert: OpaquePointer?
      guard sqlite3_prepare_v2(connection, "INSERT INTO memory(rowid,tokens) VALUES(?,?);", -1, &insert, nil) == SQLITE_OK else { throw Failure.database }
      // Finalize before the connection's failure cleanup runs.
      defer { sqlite3_finalize(insert) }
      for (offset, item) in items.enumerated() {
        sqlite3_reset(insert); sqlite3_clear_bindings(insert)
        guard sqlite3_bind_int64(insert, 1, Int64(offset + 1)) == SQLITE_OK,
              sqlite3_bind_text(insert, 2, grams(item.text).sorted().joined(separator: " "), -1, transient) == SQLITE_OK,
              sqlite3_step(insert) == SQLITE_DONE else { throw Failure.database }
      }
      guard sqlite3_exec(connection, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw Failure.database }
      var used: Int32 = 0
      var highwater: Int32 = 0
      guard sqlite3_db_status(connection, SQLITE_DBSTATUS_CACHE_USED, &used, &highwater, 0) == SQLITE_OK else { throw Failure.database }
      self.items = items
      kinds = Set(items.map(\.kind))
      lastUsed = clock.now
      // Admission estimate, not a claim about process RSS or allocator overhead.
      estimatedBytes = textBytes + items.count * MemoryLayout<MemoryRetrievalItem>.stride + Int(used)
      db = connection
      completed = true
    }

    deinit { sqlite3_close(db) }

    func search(terms: [String], queryGrams: Set<String>, limit: Int) throws -> [Hit] {
      let expression = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
      var select: OpaquePointer?
      guard sqlite3_prepare_v2(db, "SELECT rowid, bm25(memory) FROM memory WHERE tokens MATCH ? ORDER BY bm25(memory) LIMIT 30;", -1, &select, nil) == SQLITE_OK else { throw Failure.database }
      defer { sqlite3_finalize(select) }
      guard sqlite3_bind_text(select, 1, expression, -1, transient) == SQLITE_OK else { throw Failure.database }
      var hits: [Hit] = []
      while true {
        let step = sqlite3_step(select)
        if step == SQLITE_DONE { break }
        guard step == SQLITE_ROW else { throw Failure.database }
        let offset = Int(sqlite3_column_int64(select, 0)) - 1
        guard items.indices.contains(offset) else { throw Failure.database }
        guard queryGrams.intersection(grams(items[offset].text)).count >= min(2, terms.count) else { continue }
        hits.append(Hit(item: items[offset], relevance: -sqlite3_column_double(select, 1)))
      }
      return Array(hits.sorted { lhs, rhs in
        if abs(lhs.relevance - rhs.relevance) > 0.000001 { return lhs.relevance > rhs.relevance }
        return lhs.item.updatedAt > rhs.item.updatedAt
      }.prefix(max(0, min(limit, 8))))
    }
  }

  static func invalidate(kind: MemoryRetrievalItem.Kind? = nil) {
    cache.withLock { state in
      state.indexes.removeAll { index in kind.map { index.kinds.contains($0) } ?? true }
    }
  }

  static func grams(_ text: String) -> Set<String> {
    let text = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
    let runs = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    return Set(runs.flatMap { run -> [String] in
      let chars = Array(run.prefix(2_000))
      guard chars.count > 1 else { return [] }
      return (0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) }
    })
  }

  static func retrieve(_ query: String, candidates: [MemoryRetrievalItem], workspaceID: String?, personID: UUID?, limit: Int = 5) throws -> [Hit] {
    let items = Array(candidates.filter { $0.workspaceID == workspaceID && $0.personID == personID }.prefix(5_000))
    let boundedQuery = String(query.prefix(600))
    let boundedGrams = grams(boundedQuery)
    let terms = Array(boundedGrams.sorted().prefix(32))
    let queryGrams = terms.isEmpty || items.isEmpty ? [] : (boundedQuery == query ? boundedGrams : grams(query))
    return try cache.withLock { state in
      if state.workspaceID != workspaceID || state.personID != personID {
        state.indexes.removeAll()
        state.workspaceID = workspaceID
        state.personID = personID
      }
      state.indexes.removeAll { $0.lastUsed.duration(to: clock.now) >= .seconds(60) }
      // An empty authorization snapshot cannot leave previously readable text resident.
      guard !items.isEmpty else { state.indexes.removeAll(); return [] }
      let kinds = Set(items.map(\.kind))
      state.indexes.removeAll { $0.kinds == kinds && $0.items != items }
      guard !terms.isEmpty else { return [] }
      let index: Index
      if let existing = state.indexes.first(where: { $0.items == items }) {
        index = existing
#if MEMORA_HOST_CHECKS
        state.reuses += 1
#endif
      } else {
        let textBytes = items.reduce(0) { $0 + $1.text.utf8.count }
        index = try Index(items: items, textBytes: textBytes)
#if MEMORA_HOST_CHECKS
        state.builds += 1
#endif
        if textBytes <= textBudget, index.estimatedBytes <= retainedBudget {
          while state.indexes.count >= 2 || state.indexes.reduce(index.estimatedBytes, { $0 + $1.estimatedBytes }) > retainedBudget {
            state.indexes.removeFirst()
          }
          state.indexes.append(index)
        }
      }
      do {
        let result = try index.search(terms: terms, queryGrams: queryGrams, limit: limit)
        index.lastUsed = clock.now
        if let position = state.indexes.firstIndex(where: { $0 === index }) {
          state.indexes.remove(at: position)
          state.indexes.append(index)
        }
        return result
      } catch {
        state.indexes.removeAll { $0 === index }
        throw error
      }
    }
  }

#if MEMORA_HOST_CHECKS
  static var cacheChecks: (builds: Int, reuses: Int, entries: Int, estimatedBytes: Int) {
    cache.withLock { ($0.builds, $0.reuses, $0.indexes.count, $0.indexes.reduce(0) { $0 + $1.estimatedBytes }) }
  }

  static func expireCacheForChecks() {
    cache.withLock { state in
      for index in state.indexes { index.lastUsed = clock.now - .seconds(61) }
    }
  }
#endif
}
