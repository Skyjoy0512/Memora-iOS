import Foundation
import SQLite3
import CryptoKit

/// A disposable local index: current permissions are checked before indexing
/// and again before sending. It never becomes an authority for access.
actor ProjectSearchIndex {
  static let shared = ProjectSearchIndex()
  private var db: OpaquePointer?
  private var fileURL: URL
  private var synchronizedProject: UUID?
  private var synchronizedInputs: [ProjectEvidenceInput] = []
  private var synchronizedHasUniqueTargets = false
  private struct CachedInput {
    var input: ProjectEvidenceInput
    var target: String
    var fingerprint: String
  }
  private var cachedInputs: [ProjectCitation.Target: CachedInput] = [:]
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Memora/project-search-v2.sqlite")
  }

  deinit {
    if let db { sqlite3_close(db) }
  }

  enum Failure: Error { case database }

  func retrieve(question: String, projectID: UUID, inputs: [ProjectEvidenceInput]) throws -> [ProjectEvidenceChunk] {
    try open()
    try synchronize(projectID: projectID, inputs: inputs)
    let terms = ProjectContextBuilder.grams(question).sorted().prefix(32)
    let expression = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
    var result: [ProjectEvidenceChunk] = []
    if !expression.isEmpty {
      result = try query("SELECT payload FROM project_chunks WHERE project = ? AND tokens MATCH ? ORDER BY bm25(project_chunks) LIMIT 200;",
                         values: [projectID.uuidString, expression])
    }
    // Follow-ups can refer to the previous answer without repeating its words.
    if result.isEmpty {
      result = try query("SELECT payload FROM project_chunks WHERE project = ? ORDER BY rowid DESC LIMIT 200;", values: [projectID.uuidString])
    }
    return result
  }

  func remove(targets: [ProjectCitation.Target]) throws {
    clearMemoryCache()
    try open()
    try execute("BEGIN IMMEDIATE;")
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      for target in targets {
        let key = String(decoding: try encoder.encode(target), as: UTF8.self)
        try run("DELETE FROM project_chunks WHERE target = ?;", values: [key])
        try run("DELETE FROM project_manifest WHERE target = ?;", values: [key])
      }
      try execute("COMMIT;")
    } catch { try? execute("ROLLBACK;"); throw error }
  }

  func remove(projectID: UUID) throws {
    clearMemoryCache()
    try open()
    try execute("BEGIN IMMEDIATE;")
    do {
      try run("DELETE FROM project_chunks WHERE project = ?;", values: [projectID.uuidString])
      try run("DELETE FROM project_manifest WHERE project = ?;", values: [projectID.uuidString])
      try execute("COMMIT;")
    } catch { try? execute("ROLLBACK;"); throw error }
  }

  private func open() throws {
    guard db == nil else { return }
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var handle: OpaquePointer?
    guard sqlite3_open_v2(fileURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
          let handle else { if let handle { sqlite3_close(handle) }; throw Failure.database }
    db = handle
    do {
      try execute("PRAGMA journal_mode=WAL;")
      try execute("CREATE TABLE IF NOT EXISTS project_manifest (project TEXT NOT NULL, target TEXT NOT NULL, fingerprint TEXT NOT NULL, PRIMARY KEY(project,target));")
      try execute("CREATE VIRTUAL TABLE IF NOT EXISTS project_chunks USING fts5(project UNINDEXED, target UNINDEXED, payload UNINDEXED, tokens);")
    } catch {
      sqlite3_close(handle); db = nil
      throw error
    }
  }

  private func synchronize(projectID: UUID, inputs: [ProjectEvidenceInput]) throws {
    if synchronizedProject == projectID, synchronizedHasUniqueTargets, synchronizedInputs == inputs { return }
    let boundedInputs = Self.bounded(inputs)
    // Only an identical, already committed snapshot can bypass synchronization.
    // A membership, permission-filtered input, title, page, time or body change
    // fails equality. Duplicate targets keep the original sequential semantics.
    let uniqueTargets = Set(boundedInputs.map(\.target)).count == boundedInputs.count
    if synchronizedProject == projectID, uniqueTargets, synchronizedInputs == boundedInputs { return }
    let previous = synchronizedProject == projectID ? cachedInputs : [:]
    var next: [ProjectCitation.Target: CachedInput] = [:]
    let project = projectID.uuidString
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // A project refresh is atomic. Removed, moved, or newly restricted sources
    // disappear before any retrieval can use this snapshot.
    try execute("BEGIN IMMEDIATE;")
    do {
      let statement = try prepare("SELECT target, fingerprint FROM project_manifest WHERE project = ?;")
      defer { sqlite3_finalize(statement) }
      bind(project, to: statement, index: 1)
      var old: [String: String] = [:]
      while sqlite3_step(statement) == SQLITE_ROW {
        old[string(statement, column: 0)] = string(statement, column: 1)
      }
      var retained = Set<String>()
      for bounded in boundedInputs {
        let input = bounded
        let cached: CachedInput
        if let existing = previous[input.target], existing.input == bounded {
          cached = existing
        } else {
          let target = String(decoding: try encoder.encode(input.target), as: UTF8.self)
          let data = try encoder.encode(bounded)
          let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
          cached = CachedInput(input: bounded, target: target, fingerprint: fingerprint)
        }
        next[input.target] = cached
        let target = cached.target
        let fingerprint = cached.fingerprint
        retained.insert(target)
        guard old[target] != fingerprint else { continue }
        try run("DELETE FROM project_chunks WHERE project = ? AND target = ?;", values: [project, target])
        for block in bounded.blocks {
          for chunk in ProjectContextBuilder.split(block.text, projectID: projectID, target: input.target,
              title: input.title, page: block.page, time: block.time) {
            let payload = String(decoding: try encoder.encode(chunk), as: UTF8.self)
            let tokens = ProjectContextBuilder.grams(chunk.title + " " + chunk.text).sorted().joined(separator: " ")
            try run("INSERT INTO project_chunks(project,target,payload,tokens) VALUES(?,?,?,?);", values: [project, target, payload, tokens])
          }
        }
        try run("INSERT OR REPLACE INTO project_manifest(project,target,fingerprint) VALUES(?,?,?);", values: [project, target, fingerprint])
      }
      for target in old.keys where !retained.contains(target) {
        try run("DELETE FROM project_chunks WHERE project = ? AND target = ?;", values: [project, target])
        try run("DELETE FROM project_manifest WHERE project = ? AND target = ?;", values: [project, target])
      }
      try execute("COMMIT;")
      synchronizedProject = projectID
      synchronizedInputs = boundedInputs
      synchronizedHasUniqueTargets = uniqueTargets
      cachedInputs = next
    } catch { try? execute("ROLLBACK;"); throw error }
  }

  func clearMemoryCache() {
    synchronizedProject = nil
    synchronizedInputs = []
    synchronizedHasUniqueTargets = false
    cachedInputs = [:]
  }

  private static func bounded(_ inputs: [ProjectEvidenceInput]) -> [ProjectEvidenceInput] {
    var result: [ProjectEvidenceInput] = []
    var remaining = 2_000_000
    for input in inputs {
      guard remaining > 0 else { break }
      var bounded = input
      bounded.blocks = []
      for block in input.blocks {
        guard remaining > 0 else { break }
        let limit = min(200_000, remaining)
        let count = block.text.count
        let text = count <= limit ? block.text : String(block.text.prefix(limit))
        remaining -= min(count, limit)
        bounded.blocks.append(ProjectSourceText(text: text, page: block.page, time: block.time))
      }
      result.append(bounded)
    }
    return result
  }

  private func query(_ sql: String, values: [String]) throws -> [ProjectEvidenceChunk] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() { bind(value, to: statement, index: Int32(offset + 1)) }
    var result: [ProjectEvidenceChunk] = []
    let decoder = JSONDecoder()
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW else { throw Failure.database }
      guard let chunk = try? decoder.decode(ProjectEvidenceChunk.self, from: Data(string(statement, column: 0).utf8)) else { throw Failure.database }
      result.append(chunk)
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Failure.database }
    return statement
  }

  private func bind(_ value: String, to statement: OpaquePointer, index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, Self.transient)
  }

  private func string(_ statement: OpaquePointer, column: Int32) -> String {
    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
  }

  private func run(_ sql: String, values: [String]) throws {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() { bind(value, to: statement, index: Int32(offset + 1)) }
    guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.database }
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.database }
  }
}
