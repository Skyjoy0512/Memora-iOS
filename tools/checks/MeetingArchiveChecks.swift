import CryptoKit
import Darwin
import Foundation
import SQLite3

/// Checks the record row archive against the real store: the switch from the
/// collection document, one-record writes, order changes, damage, rollback and
/// the cost of each at 100 to 50,000 records.
@main
enum MeetingArchiveChecks {
  private static let mediaNames = ["play.m4a", "part.m4a", "note.jpg"]

  static func main() throws {
    try mediaNames.forEach { name in
      try Data(name.utf8).write(to: MediaFiles.root.appendingPathComponent(name))
    }
    switch CommandLine.arguments[2] {
    case "contract":
      try migratesAndRetiresCollection()
      try writesOnlyChangedRows()
      try appliesInsertionsRemovalsAndOrder()
      try rejectsDamagedRowsAndFallsBack()
      try rejectsMismatchedRows()
      try writesThePreparedPayload()
      try rollsBackOnFailedWrite()
      print("Meeting archive: migration, single-row writes, ordering, damaged rows, rollback passed.")
    default:
      guard let count = Int(CommandLine.arguments[2]), (100...50_000).contains(count) else {
        preconditionFailure("Unexpected synthetic count")
      }
      try scale(count)
    }
  }

  // MARK: - Contract

  private static func migratesAndRetiresCollection() throws {
    let store = try open("archive-switch")
    let rows = try fixtureRows(count: 4)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    guard case .absent = MeetingArchive.load(store) else {
      preconditionFailure("A store without rows must report the collection as the authority")
    }

    let records = try JSONDecoder().decode([Meeting].self, from: original)
    try commit(store, from: nil, to: records)
    precondition(data(store, MeetingRowStaging.collectionKey) == nil)
    precondition(data(store, MeetingArchive.legacyKey) == original)
    guard case .records(let loaded) = MeetingArchive.load(store) else {
      preconditionFailure("Rows written by the switch were not readable")
    }
    precondition(loaded == records)
    guard let firstRow = rowDocument(store, id: records[0].id) else {
      preconditionFailure("First row is missing")
    }
    precondition(String(decoding: firstRow.dropFirst(32), as: UTF8.self).contains("futureField"),
                 "An untouched record must keep the bytes it was stored with")
    let keysAfterSwitch = try rowKeys(store)
    precondition(keysAfterSwitch.count == records.count)
  }

  private static func writesOnlyChangedRows() throws {
    let store = try open("archive-edit")
    let records = try seeded(store, count: 12, name: "archive-edit")
    var edited = records
    edited[5].title = "編集した記録"
    edited[5].summary = "編集した本文"
    let before = try rowDocuments(store)
    let change = try MeetingArchive.change(from: records, to: edited, collection: nil)
    precondition(change.documents.count == 1 && change.removals.isEmpty)
    precondition(!change.manifestChanged)
    try commit(store, change: change)
    let after = try rowDocuments(store)
    let changed = before.filter { after[$0.key] != $0.value }
    precondition(changed.count == 1 && changed.first?.key == MeetingArchive.rowKey(records[5].id))
    guard case .records(let loaded) = MeetingArchive.load(store) else {
      preconditionFailure("Edited rows were not readable")
    }
    precondition(loaded == edited)
  }

  private static func appliesInsertionsRemovalsAndOrder() throws {
    let store = try open("archive-order")
    let records = try seeded(store, count: 8, name: "archive-order")
    let added = Meeting(id: UUID(), title: "追加した記録", createdAt: .now, duration: 0,
                        source: .recording, status: .ready, summary: "", keyPoints: [], decisions: [],
                        openQuestions: [], transcript: [], spaceID: nil)
    let reordered = [added] + records.reversed().dropFirst(2)
    let change = try MeetingArchive.change(from: records, to: reordered, collection: nil)
    precondition(change.manifestChanged)
    precondition(change.removals.count == 2)
    try commit(store, change: change)
    guard case .records(let loaded) = MeetingArchive.load(store) else {
      preconditionFailure("Reordered rows were not readable")
    }
    precondition(loaded == reordered)
    let keysAfterReorder = try rowKeys(store)
    precondition(keysAfterReorder.count == reordered.count)
  }

  private static func rejectsDamagedRowsAndFallsBack() throws {
    let store = try open("archive-damage")
    let records = try seeded(store, count: 3, name: "archive-damage")
    try sql("archive-damage", """
      UPDATE documents SET data = x'00' WHERE key = '\(MeetingArchive.rowKey(records[1].id))';
      """)
    guard case .invalid = MeetingArchive.load(store) else {
      preconditionFailure("A damaged row must not be served")
    }
    try sql("archive-damage", "DELETE FROM documents WHERE key = '\(MeetingArchive.manifestKey)';")
    guard case .absent = MeetingArchive.load(store) else {
      preconditionFailure("A missing manifest must report the collection as the authority")
    }
    precondition(data(store, MeetingArchive.legacyKey) != nil,
                 "The previous collection must survive a damaged archive")
  }

  /// A row whose payload names a different record, a manifest that lists a row
  /// that is not there, and an extra row are all refused rather than served.
  private static func rejectsMismatchedRows() throws {
    for damage in ["foreign", "missing", "extra"] {
      let store = try open("archive-\(damage)")
      let records = try seeded(store, count: 4, name: "archive-\(damage)")
      let database = "archive-\(damage)"
      switch damage {
      case "foreign":
        // Row 1 now carries record 0's payload, digest and all.
        let donor = data(store, MeetingArchive.rowKey(records[0].id))!
        try sql(database, "UPDATE documents SET data = X'\(donor.map { String(format: "%02x", $0) }.joined())' "
          + "WHERE key = '\(MeetingArchive.rowKey(records[1].id))';")
      case "missing":
        try sql(database, "DELETE FROM documents WHERE key = '\(MeetingArchive.rowKey(records[2].id))';")
      default:
        try sql(database, "INSERT OR REPLACE INTO documents (key, data, updated_at) VALUES "
          + "('\(MeetingArchive.rowKey(UUID()))', X'00', 0);")
      }
      guard case .invalid = MeetingArchive.load(store) else {
        preconditionFailure("A \(damage) row set was served")
      }
      // The rows are refused, not repaired; the caller falls back to the copy.
      let rows = try rowKeys(store)
      precondition(damage == "extra" ? rows.count == 5 : rows.count == (damage == "missing" ? 3 : 4))
    }
  }

  /// An edit hands the save the record it already encoded off the main actor.
  /// The archive writes those bytes rather than encoding the record again.
  private static func writesThePreparedPayload() throws {
    let store = try open("archive-prepared")
    let records = try seeded(store, count: 3, name: "archive-prepared")
    var edited = records
    edited[1].title = "準備済みの題名"
    let encoder = JSONEncoder()
    let payload = try encoder.encode(edited[1])
    let change = try MeetingArchive.change(from: records, to: edited, collection: nil,
                                           prepared: [edited[1].id: payload])
    precondition(change.documents.count == 1)
    let document = change.documents[0].data
    precondition(Data(document.dropFirst(32)) == payload,
                 "The prepared bytes were not the ones written")
    try commit(store, change: change)
    guard case .records(let loaded) = MeetingArchive.load(store) else {
      preconditionFailure("The prepared row was not readable")
    }
    precondition(loaded == edited)
  }

  private static func rollsBackOnFailedWrite() throws {
    let store = try open("archive-rollback")
    let rows = try fixtureRows(count: 3)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let records = try JSONDecoder().decode([Meeting].self, from: original)
    try sql("archive-rollback", """
      CREATE TRIGGER reject_manifest BEFORE INSERT ON documents
      WHEN NEW.key = '\(MeetingArchive.manifestKey)'
      BEGIN SELECT RAISE(ABORT, 'synthetic disk failure'); END;
      """)
    do {
      try commit(store, from: nil, to: records)
      preconditionFailure("A failed write was accepted")
    } catch is LocalStore.StoreError {}
    precondition(data(store, MeetingRowStaging.collectionKey) == original)
    precondition(data(store, MeetingArchive.manifestKey) == nil)
    let keysAfterFailure = try rowKeys(store)
    precondition(keysAfterFailure.isEmpty)
  }

  // MARK: - Scale

  private static func scale(_ count: Int) throws {
    let name = "archive-scale-\(count)"
    let store = try open(name)
    let rows = try fixtureRows(count: count)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let records = try JSONDecoder().decode([Meeting].self, from: original)

    // The way the app stored records before: encode the whole collection and
    // rewrite it.
    var legacyEncode: [Double] = []
    var legacyWrite: [Double] = []
    for _ in 0..<3 {
      let encodeStart = ContinuousClock.now
      let encoded = try JSONEncoder().encode(records)
      let encodedAt = ContinuousClock.now
      try store.write(MeetingRowStaging.collectionKey, data: encoded)
      let writtenAt = ContinuousClock.now
      legacyEncode.append(milliseconds(encodeStart, encodedAt))
      legacyWrite.append(milliseconds(encodedAt, writtenAt))
    }
    try store.write(MeetingRowStaging.collectionKey, data: original)

    let switchStart = ContinuousClock.now
    try commit(store, from: nil, to: records)
    let switchEnd = ContinuousClock.now

    var editTimes: [Double] = []
    var current = records
    for trial in 0..<9 {
      let index = (trial * 7 + 3) % current.count
      let previous = current
      current[index].title = "編集\(trial)"
      let start = ContinuousClock.now
      let edit = try MeetingArchive.change(from: previous, to: current, collection: nil)
      try commit(store, change: edit)
      let end = ContinuousClock.now
      editTimes.append(milliseconds(start, end))
      precondition(edit.documents.count == 1)
    }

    var manifestTimes: [Double] = []
    var scanTimes: [Double] = []
    for _ in 0..<3 {
      guard let manifestData = data(store, MeetingArchive.manifestKey) else {
        preconditionFailure("Missing manifest")
      }
      let start = ContinuousClock.now
      let manifest = try JSONDecoder().decode(MeetingArchive.Manifest.self, from: manifestData)
      let decodedAt = ContinuousClock.now
      var seen = 0
      _ = try store.scanDocuments(inKeyRange: MeetingArchive.keyRange) { _, _ in seen += 1 }
      let scannedAt = ContinuousClock.now
      manifestTimes.append(milliseconds(start, decodedAt))
      scanTimes.append(milliseconds(decodedAt, scannedAt))
      precondition(manifest.ids.count == count && seen == count)
    }

    var archiveRead: [Double] = []
    for _ in 0..<3 {
      let start = ContinuousClock.now
      let loaded: [Meeting]
      switch MeetingArchive.load(store) {
      case .records(let records): loaded = records
      default: preconditionFailure("Archive became unreadable")
      }
      let end = ContinuousClock.now
      precondition(loaded == current)
      archiveRead.append(milliseconds(start, end))
    }

    var blobRead: [Double] = []
    var blobDecode: [Double] = []
    for _ in 0..<3 {
      let start = ContinuousClock.now
      guard let bytes = data(store, MeetingArchive.legacyKey) else { preconditionFailure("Missing copy") }
      let readAt = ContinuousClock.now
      let decoded = try JSONDecoder().decode([Meeting].self, from: bytes)
      let end = ContinuousClock.now
      precondition(decoded.count == count)
      blobRead.append(milliseconds(start, readAt))
      blobDecode.append(milliseconds(readAt, end))
    }

    let metrics: [String: Any] = [
      "records": count,
      "collectionBytes": original.count,
      "legacyEncodeMS": median(legacyEncode),
      "legacyWriteMS": median(legacyWrite),
      "switchMS": milliseconds(switchStart, switchEnd),
      "singleEditMS": median(editTimes),
      "archiveLoadMS": median(archiveRead),
      "blobReadMS": median(blobRead),
      "blobDecodeMS": median(blobDecode),
      "manifestDecodeMS": median(manifestTimes),
      "rowScanMS": median(scanTimes),
    ]
    print(String(decoding: try JSONSerialization.data(withJSONObject: metrics, options: .sortedKeys), as: UTF8.self))
  }

  // MARK: - Helpers

  private static func seeded(_ store: LocalStore, count: Int, name: String) throws -> [Meeting] {
    let rows = try fixtureRows(count: count)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let records = try JSONDecoder().decode([Meeting].self, from: original)
    try commit(store, from: nil, to: records)
    return records
  }

  /// The same sequence the app's store performs for a record save.
  private static func commit(_ store: LocalStore, from previous: [Meeting]?, to meetings: [Meeting]) throws {
    let source: Data? = data(store, MeetingRowStaging.collectionKey)
    var change = try MeetingArchive.change(from: previous, to: meetings, collection: source)
    change.removals = MeetingArchive.staleRemovals(for: change, in: store)
    try commit(store, change: change, source: source)
  }

  private static func commit(_ store: LocalStore, change: MeetingArchive.Change,
                             source: Data? = nil) throws {
    var documents = change.documents
    if change.manifestChanged || change.rebuild != nil {
      documents.append((key: MeetingArchive.manifestKey,
                        data: try MeetingArchive.manifestData(change.manifest)))
    }
    if let source { documents.append((key: MeetingArchive.legacyKey, data: source)) }
    let landed = try store.applyBatch(
      writes: documents, removing: change.removals,
      expecting: change.rebuild != nil ? [(MeetingRowStaging.collectionKey, source)] : [])
    precondition(landed)
  }

  private static func rowKeys(_ store: LocalStore) throws -> [String] {
    var keys: [String] = []
    _ = try store.scanDocuments(inKeyRange: MeetingArchive.keyRange) { key, _ in keys.append(key) }
    return keys
  }

  private static func rowDocuments(_ store: LocalStore) throws -> [String: Data] {
    var values: [String: Data] = [:]
    _ = try store.scanDocuments(inKeyRange: MeetingArchive.keyRange) { key, data in values[key] = data }
    return values
  }

  private static func rowDocument(_ store: LocalStore, id: UUID) -> Data? {
    data(store, MeetingArchive.rowKey(id))
  }

  private static func fixtureRows(count: Int) throws -> [Data] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return try (0..<count).map { ordinal in
      let id = UUID(uuidString: String(format: "23000000-0000-4000-8000-%012d", ordinal + 1))!
      var record = Meeting(id: id, title: "記録\(ordinal) { \"引用\" } \\ パス",
        createdAt: now, duration: 27, source: .importFile, status: .ready,
        summary: "本文・空白\n改行と日付", keyPoints: ["確認"], decisions: [], openQuestions: [],
        transcript: [], privacy: RecordPrivacy(updatedAt: now))
      if ordinal == 0 {
        record.rawAudioReference = "play.m4a"
        record.originalAudioFileNames = ["part.m4a"]
        record.photoFileNames = ["note.jpg"]
      }
      let encoded = try encoder.encode(record)
      if ordinal != 0 { return encoded }
      let futureField = Data(#"{"futureField":{"value":"brackets } [ and \"quote\"","list":[1,2]},"#.utf8)
      return futureField + encoded.dropFirst()
    }
  }

  private static func collection(_ rows: [Data]) -> Data {
    var result = Data(" [ \n".utf8)
    for (index, row) in rows.enumerated() {
      if index > 0 { result.append(contentsOf: ",\n".utf8) }
      result.append(row)
    }
    result.append(contentsOf: "\n ] \n".utf8)
    return result
  }

  private static func open(_ name: String) throws -> LocalStore {
    let store = LocalStore(fileURL: MediaFiles.root.appendingPathComponent("\(name).sqlite"))
    try store.prepare()
    return store
  }

  private static func data(_ store: LocalStore, _ key: String) -> Data? {
    switch store.readOutcome(key) {
    case .data(let value): value
    case .missing: nil
    case .failed: preconditionFailure("Could not read fixture")
    }
  }

  private static func sql(_ name: String, _ statement: String) throws {
    var db: OpaquePointer?
    let url = MediaFiles.root.appendingPathComponent("\(name).sqlite")
    precondition(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
  }

  private static func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty)
    return values.sorted()[values.count / 2]
  }

  private static func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
    let time = start.duration(to: end).components
    return Double(time.seconds) * 1_000 + Double(time.attoseconds) / 1e15
  }
}

enum MediaFiles {
  static let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

  static func resolve(_ name: String) -> URL? {
    guard ["play.m4a", "part.m4a", "note.jpg"].contains(name) else { return nil }
    let url = root.appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  static func reference(for url: URL) -> String? { resolve(url.lastPathComponent) == url ? url.lastPathComponent : nil }
  static func writePhoto(_ data: Data) -> String? { preconditionFailure("Decoding should leave the fixture files alone") }
  static func deletePhoto(_ name: String) { preconditionFailure("Decoding should leave the fixture files alone") }
}
