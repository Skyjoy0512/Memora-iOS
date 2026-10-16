import Foundation
import SQLite3

/// Disposable FTS5 retrieval. Callers supply only currently authorized candidates.
enum MemoryRetrievalOrchestrator {
  struct Hit {
    var item: MemoryRetrievalItem
    var relevance: Double
  }
  enum Failure: Error { case database }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
    let terms = grams(String(query.prefix(600))).sorted().prefix(32)
    guard !terms.isEmpty, !items.isEmpty else { return [] }
    var db: OpaquePointer?
    guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db else { throw Failure.database }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, "CREATE VIRTUAL TABLE memory USING fts5(tokens); BEGIN;", nil, nil, nil) == SQLITE_OK else { throw Failure.database }
    var insert: OpaquePointer?
    guard sqlite3_prepare_v2(db, "INSERT INTO memory(rowid,tokens) VALUES(?,?);", -1, &insert, nil) == SQLITE_OK else { throw Failure.database }
    defer { sqlite3_finalize(insert) }
    for (index, item) in items.enumerated() {
      sqlite3_reset(insert); sqlite3_clear_bindings(insert)
      sqlite3_bind_int64(insert, 1, Int64(index + 1))
      sqlite3_bind_text(insert, 2, grams(item.text).sorted().joined(separator: " "), -1, transient)
      guard sqlite3_step(insert) == SQLITE_DONE else { throw Failure.database }
    }
    guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw Failure.database }
    let expression = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
    var select: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT rowid, bm25(memory) FROM memory WHERE tokens MATCH ? ORDER BY bm25(memory) LIMIT 30;", -1, &select, nil) == SQLITE_OK else { throw Failure.database }
    defer { sqlite3_finalize(select) }
    sqlite3_bind_text(select, 1, expression, -1, transient)
    var hits: [Hit] = []
    while sqlite3_step(select) == SQLITE_ROW {
      let index = Int(sqlite3_column_int64(select, 0)) - 1
      guard items.indices.contains(index) else { continue }
      let overlap = grams(query).intersection(grams(items[index].text)).count
      guard overlap >= min(2, terms.count) else { continue }
      hits.append(Hit(item: items[index], relevance: -sqlite3_column_double(select, 1)))
    }
    return Array(hits.sorted { lhs, rhs in
      if abs(lhs.relevance - rhs.relevance) > 0.000001 { return lhs.relevance > rhs.relevance }
      return lhs.item.updatedAt > rhs.item.updatedAt
    }.prefix(max(0, min(limit, 8))))
  }
}
