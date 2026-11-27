import CryptoKit
import Darwin
import Foundation
import SQLite3

@main
enum MeetingRowStagingChecks {
  private static let mediaNames = ["play.m4a", "part.m4a", "note.jpg"]

  static func main() throws {
    switch CommandLine.arguments[2] {
    case "interrupt":
      let store = try open("recovery")
      let first = try MeetingRowStaging(store: store).stage(maximumRows: 1)
      precondition(first.stagedCount == 1)
      // Exit without unwinding the Swift stack or closing the SQLite handle.
      Darwin._exit(86)
    case "recovery":
      try mediaNames.forEach { name in
        try Data(name.utf8).write(to: MediaFiles.root.appendingPathComponent(name))
      }
      try recoversAfterProcessExit()
      try rejectsConflictingWriters()
      try rollsBackMidBatchAndCancellation()
      try rejectsIncompleteOrInvalidStaging()
      try validatesEmptyCollection()
      try readsOnlySealedPages()
      try rejectsOversizedPage()
      print("Meeting row staging: process reopen, transactional rollback, cancellation, competing writers, corrupt or duplicate rows, missing media and sealed page checks passed.")
    default:
      guard let count = Int(CommandLine.arguments[2]), (100...50_000).contains(count) else {
        preconditionFailure("Unexpected synthetic count")
      }
      try scale(count)
    }
  }

  private static func recoversAfterProcessExit() throws {
    let store = try open("recovery")
    let rows = try fixtureRows(count: 3)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = [MediaFiles.root.path, "interrupt"]
    try child.run()
    child.waitUntilExit()
    precondition(child.terminationStatus == 86)

    let reopened = try open("recovery")
    let checkpoint = try saved(reopened)
    precondition(checkpoint.stagedCount == 1 && !checkpoint.verified)
    let staging = try MeetingRowStaging(store: reopened)
    let complete = try staging.stage(maximumRows: 2)
    precondition(complete.generation == checkpoint.generation && complete.stagedCount == 3)
    let verified = try staging.verify(mediaExists: mediaExists)
    let repeated = try staging.verify(mediaExists: mediaExists)
    precondition(repeated == verified && verified.verified)
    try assertRows(rows, store: reopened, checkpoint: verified)
    precondition(data(reopened, MeetingRowStaging.collectionKey) == original)
  }

  private static func rejectsConflictingWriters() throws {
    let store = try open("competing-source")
    let writer = try open("competing-source")
    let rows = try fixtureRows(count: 3)
    let original = collection(rows)
    let editedRows = [rows[2], rows[0]]
    let replacement = collection(editedRows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let old = try MeetingRowStaging(store: store)
    let interrupted = try old.stage(maximumRows: 1)
    try writer.write(MeetingRowStaging.collectionKey, data: replacement)
    expectFailure(.conflict) { try old.stage(maximumRows: 2) }
    let unchanged = try saved(store)
    precondition(unchanged == interrupted)
    precondition(data(store, interrupted.rowKey(0)) == rows[0])
    precondition(data(store, interrupted.rowKey(1)) == nil)

    let replacementStage = try MeetingRowStaging(store: store)
    let new = try replacementStage.stage(maximumRows: 4)
    precondition(new.generation != interrupted.generation && new.count == 2)
    precondition(data(store, interrupted.rowKey(0)) == nil)
    var checksBeforeSeal = 0
    expectFailure(.conflict) {
      try replacementStage.verify(mediaExists: mediaExists) {
        checksBeforeSeal += 1
        if checksBeforeSeal == new.count + 1 {
          try writer.write(MeetingRowStaging.collectionKey, data: original)
        }
      }
    }
    let pending = try saved(store)
    precondition(pending == new && !pending.verified)
    precondition(data(store, MeetingRowStaging.collectionKey) == original)

    let recovering = try MeetingRowStaging(store: writer)
    let ready = try recovering.stage(maximumRows: 3)
    let verified = try recovering.verify(mediaExists: mediaExists)
    precondition(verified.generation == ready.generation)
    try assertRows(rows, store: writer, checkpoint: verified)
    precondition(data(writer, MeetingRowStaging.collectionKey) == original)

    let parallel = try open("competing-checkpoint")
    let other = try open("competing-checkpoint")
    try parallel.write(MeetingRowStaging.collectionKey, data: original)
    let first = try MeetingRowStaging(store: parallel)
    let second = try MeetingRowStaging(store: other)
    var checks = 0
    expectFailure(.conflict) {
      try first.stage(maximumRows: 2) {
        checks += 1
        if checks == 2 { _ = try second.stage(maximumRows: 1) }
      }
    }
    let winner = try saved(parallel)
    precondition(winner.stagedCount == 1 && data(parallel, winner.rowKey(1)) == nil)

    let complete = try second.stage(maximumRows: 2)
    var verifyChecks = 0
    expectFailure(.conflict) {
      try second.verify(mediaExists: mediaExists) {
        verifyChecks += 1
        if verifyChecks == complete.count + 1 {
          try parallel.write(complete.rowKey(0), data: rows[1])
        }
      }
    }
    let stillUnverified = try saved(other)
    precondition(!stillUnverified.verified && data(other, MeetingRowStaging.collectionKey) == original)
  }

  private static func rollsBackMidBatchAndCancellation() throws {
    let store = try open("rollback")
    let rows = try fixtureRows(count: 4)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let staging = try MeetingRowStaging(store: store)
    let first = try staging.stage(maximumRows: 1)
    try sql("rollback", """
      CREATE TRIGGER reject_checkpoint BEFORE INSERT ON documents
      WHEN NEW.key = '\(MeetingRowStaging.checkpointKey)'
      BEGIN SELECT RAISE(ABORT, 'synthetic disk failure'); END;
      """)
    do {
      _ = try staging.stage(maximumRows: 3)
      preconditionFailure("A failed checkpoint was accepted")
    } catch is LocalStore.StoreError {}
    let afterFailure = try saved(store)
    precondition(afterFailure == first && data(store, first.rowKey(1)) == nil)
    try sql("rollback", "DROP TRIGGER reject_checkpoint;")

    var checks = 0
    do {
      _ = try staging.stage(maximumRows: 3) {
        checks += 1
        if checks == 3 { throw CancellationError() }
      }
      preconditionFailure("Cancelled staging was published")
    } catch is CancellationError {}
    let afterCancellation = try saved(store)
    precondition(afterCancellation == first && data(store, first.rowKey(1)) == nil)
    let complete = try staging.stage(maximumRows: 3)
    try sql("rollback", """
      CREATE TRIGGER reject_seal BEFORE INSERT ON documents
      WHEN NEW.key = '\(MeetingRowStaging.checkpointKey)'
      BEGIN SELECT RAISE(ABORT, 'synthetic seal failure'); END;
      """)
    do {
      _ = try staging.verify(mediaExists: mediaExists)
      preconditionFailure("A failed seal was accepted")
    } catch is LocalStore.StoreError {}
    let afterSealFailure = try saved(store)
    precondition(afterSealFailure == complete && data(store, complete.pageKey(0)) == nil)
    try sql("rollback", "DROP TRIGGER reject_seal;")
    let ready = try staging.verify(mediaExists: mediaExists)
    try assertRows(rows, store: store, checkpoint: ready)
    precondition(data(store, MeetingRowStaging.collectionKey) == original)
  }

  private static func rejectsIncompleteOrInvalidStaging() throws {
    let store = try open("invalid")
    let rows = try fixtureRows(count: 2)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let staging = try MeetingRowStaging(store: store)
    _ = try staging.stage(maximumRows: 1)
    expectFailure(.unfinished) { try staging.verify(mediaExists: mediaExists) }
    let checkpoint = try staging.stage(maximumRows: 1)
    try store.write(checkpoint.rowKey(1), data: rows[0])
    expectFailure(.invalidRow(1)) { try staging.verify(mediaExists: mediaExists) }
    try staging.discard()
    precondition(data(store, checkpoint.rowKey(0)) == nil && data(store, checkpoint.rowKey(1)) == nil)
    precondition(data(store, MeetingRowStaging.checkpointKey) == nil)
    precondition(data(store, MeetingRowStaging.collectionKey) == original)
    let repaired = try staging.stage(maximumRows: 2)
    precondition(repaired.generation != checkpoint.generation)

    let photo = MediaFiles.root.appendingPathComponent("note.jpg")
    let photoBytes = try Data(contentsOf: photo)
    try FileManager.default.removeItem(at: photo)
    expectFailure(.missingMedia(0)) { try staging.verify(mediaExists: mediaExists) }
    try photoBytes.write(to: photo)
    let unverified = try saved(store)
    precondition(!unverified.verified && data(store, MeetingRowStaging.collectionKey) == original)
    _ = try staging.verify(mediaExists: mediaExists)

    try store.write(MeetingRowStaging.collectionKey, data: collection([rows[0], rows[0]]))
    let duplicate = try MeetingRowStaging(store: store)
    _ = try duplicate.stage(maximumRows: 2)
    expectFailure(.duplicateRecordID) { try duplicate.verify(mediaExists: mediaExists) }

    for malformed in ["[{]}", "[{} ,]", "[{}]{}", "[1]", "[{},{}"] {
      try store.write(MeetingRowStaging.collectionKey, data: Data(malformed.utf8))
      expectFailure(.malformedCollection) { try MeetingRowStaging(store: store) }
    }
    try store.write(MeetingRowStaging.collectionKey, data: Data("[{}]".utf8))
    let invalidRecord = try MeetingRowStaging(store: store)
    expectFailure(.invalidRow(0)) { try invalidRecord.stage(maximumRows: 1) }
  }

  private static func validatesEmptyCollection() throws {
    let store = try open("empty")
    expectFailure(.missingSource) { try MeetingRowStaging(store: store) }
    let source = Data(" \t [ \n ] \n ".utf8)
    try store.write(MeetingRowStaging.collectionKey, data: source)
    let staging = try MeetingRowStaging(store: store)
    _ = try staging.stage(maximumRows: 1)
    let verified = try staging.verify(mediaExists: mediaExists)
    precondition(verified.count == 0 && verified.verified)
    precondition(data(store, MeetingRowStaging.collectionKey) == source)
    let reader = try MeetingRowStaging.SealedReader(store: store, verified: verified)
    precondition(reader.count == 0 && reader.pageCount == 0)
    expectFailure(.outOfRange) { try reader.page(0) }
  }

  private static func readsOnlySealedPages() throws {
    let store = try open("paged")
    let writer = try open("paged")
    let rows = try fixtureRows(count: 131)
    let original = collection(rows)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let staging = try MeetingRowStaging(store: store)
    let pending = try staging.stage(maximumRows: rows.count)
    expectFailure(.unfinished) { try MeetingRowStaging.SealedReader(store: store, verified: pending) }
    let verified = try staging.verify(mediaExists: mediaExists)
    let makeReader = { try MeetingRowStaging.SealedReader(store: store, verified: verified) }
    var reader = try makeReader()
    let expected = try JSONDecoder().decode([Meeting].self, from: original)
    precondition(reader.count == rows.count && reader.pageCount == 3)
    let pageRecords = try (0..<reader.pageCount).flatMap { index -> [Meeting] in
      let page = try reader.page(index)
      precondition(page.offset == index * MeetingRowStaging.pageSize)
      precondition(page.records.count <= MeetingRowStaging.pageSize)
      return page.records
    }
    precondition(pageRecords == expected)
    expectFailure(.outOfRange) { try reader.page(-1) }
    expectFailure(.outOfRange) { try reader.page(Int.max) }
    do {
      _ = try reader.page(0) { throw CancellationError() }
      preconditionFailure("Cancelled page was returned")
    } catch is CancellationError {}

    var checks = 0
    expectFailure(.conflict) {
      try reader.page(0) {
        checks += 1
        if checks == MeetingRowStaging.pageSize + 2 {
          try writer.write(verified.rowKey(1), data: rows[0])
        }
      }
    }
    reader = try makeReader()
    expectFailure(.invalidRow(1)) { try reader.page(0) }
    let unaffectedPage = try reader.page(1)
    precondition(unaffectedPage.records == Array(expected[64..<128]))
    try writer.write(verified.rowKey(1), data: rows[1])
    try writer.remove(verified.rowKey(128))
    reader = try makeReader()
    expectFailure(.invalidRow(128)) { try reader.page(2) }
    try writer.write(verified.rowKey(128), data: rows[128])

    let digestKey = verified.pageKey(2)
    let originalDigest = data(store, digestKey)!
    var changedDigest = originalDigest
    changedDigest[0] ^= 1
    try writer.write(digestKey, data: changedDigest)
    reader = try makeReader()
    expectFailure(.invalidPage(2)) { try reader.page(2) }
    try writer.remove(digestKey)
    reader = try makeReader()
    expectFailure(.invalidPage(2)) { try reader.page(2) }
    try writer.write(digestKey, data: originalDigest)
    reader = try makeReader()

    var changedCheckpoint = verified
    changedCheckpoint.pageDigests?[0][0] ^= 1
    try writer.write(MeetingRowStaging.checkpointKey, data: JSONEncoder().encode(changedCheckpoint))
    expectFailure(.conflict) { try reader.page(0) }
    expectFailure(.conflict) { try makeReader() }
    try writer.write(MeetingRowStaging.checkpointKey, data: JSONEncoder().encode(verified))
    reader = try makeReader()
    try staging.discard()
    expectFailure(.conflict) { try reader.page(0) }
    precondition(data(store, digestKey) == nil && data(store, MeetingRowStaging.collectionKey) == original)
  }

  private static func rejectsOversizedPage() throws {
    let store = try open("oversized-page")
    let rows = try fixtureRows(count: 2)
    var records = try rows.map { try JSONDecoder().decode(Meeting.self, from: $0) }
    for index in records.indices { records[index].summary = String(repeating: "x", count: 4 * 1_024 * 1_024) }
    let original = try JSONEncoder().encode(records)
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let staging = try MeetingRowStaging(store: store)
    _ = try staging.stage(maximumRows: 2)
    _ = try staging.stage(maximumRows: 2)
    let verified = try staging.verify(mediaExists: mediaExists)
    let reader = try MeetingRowStaging.SealedReader(store: store, verified: verified)
    expectFailure(.pageTooLarge) { try reader.page(0) }
    precondition(data(store, MeetingRowStaging.collectionKey) == original)
  }

  private static func scale(_ count: Int) throws {
    try mediaNames.forEach { name in
      try Data(name.utf8).write(to: MediaFiles.root.appendingPathComponent(name))
    }
    let store = try open("scale-\(count)")
    let rows = try fixtureRows(count: count)
    let original = collection(rows)
    let mediaBefore = try mediaDigests()
    try store.write(MeetingRowStaging.collectionKey, data: original)
    let start = ContinuousClock.now
    let staging = try MeetingRowStaging(store: store)
    var checkpoint: MeetingRowStaging.Checkpoint
    var batches = 0
    repeat {
      checkpoint = try staging.stage(maximumRows: 1_000)
      batches += 1
    } while checkpoint.stagedCount < count
    let staged = ContinuousClock.now
    let verified = try staging.verify(mediaExists: mediaExists)
    let finished = ContinuousClock.now
    let current = try mediaDigests()
    precondition(current == mediaBefore && verified.count == count && verified.verified)
    precondition(data(store, MeetingRowStaging.collectionKey) == original)
    var metrics: [String: Any] = ["records": count, "sourceBytes": original.count, "batches": batches,
      "stageMS": milliseconds(start, staged), "verifyMS": milliseconds(staged, finished)]
    if count == 50_000 {
      let reopened = try open("scale-\(count)")
      metrics["warmReads"] = try measureWarmReads(store: reopened, verified: verified)
    }
    print(String(decoding: try JSONSerialization.data(withJSONObject: metrics, options: .sortedKeys), as: UTF8.self))
  }

  private static func measureWarmReads(store: LocalStore, verified: MeetingRowStaging.Checkpoint) throws -> [String: Any] {
    var checkpointTimes: [Double] = []
    var firstPageTimes: [Double] = []
    var latePageTimes: [Double] = []
    var blobReadTimes: [Double] = []
    var blobDecodeTimes: [Double] = []
    var blobTotalTimes: [Double] = []
    var firstPageBytes = 0
    var latePageBytes = 0
    let latePageIndex = verified.pageCount - 2
    let trials = 5
    for _ in 0..<trials {
      let checkpointStart = ContinuousClock.now
      let reader = try MeetingRowStaging.SealedReader(store: store, verified: verified)
      let checkpointEnd = ContinuousClock.now
      let first = try reader.page(0)
      let firstEnd = ContinuousClock.now
      let late = try reader.page(latePageIndex)
      let lateEnd = ContinuousClock.now
      checkpointTimes.append(milliseconds(checkpointStart, checkpointEnd))
      firstPageTimes.append(milliseconds(checkpointEnd, firstEnd))
      latePageTimes.append(milliseconds(firstEnd, lateEnd))
      firstPageBytes = first.payloadBytes
      latePageBytes = late.payloadBytes

      let blobStart = ContinuousClock.now
      guard let bytes = data(store, MeetingRowStaging.collectionKey) else { preconditionFailure("Missing original") }
      let blobRead = ContinuousClock.now
      let decoded = try JSONDecoder().decode([Meeting].self, from: bytes)
      let blobEnd = ContinuousClock.now
      blobReadTimes.append(milliseconds(blobStart, blobRead))
      blobDecodeTimes.append(milliseconds(blobRead, blobEnd))
      blobTotalTimes.append(milliseconds(blobStart, blobEnd))
      precondition(decoded.count == verified.count)
      for page in [first, late] {
        precondition(page.records.count == MeetingRowStaging.pageSize)
        precondition(page.records.elementsEqual(decoded[page.offset..<(page.offset + page.records.count)]))
      }
    }
    func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    return ["trials": trials, "pageSize": MeetingRowStaging.pageSize, "lateOffset": latePageIndex * MeetingRowStaging.pageSize,
      "firstPageBytes": firstPageBytes, "latePageBytes": latePageBytes, "checkpointOpenMS": median(checkpointTimes),
      "firstPageMS": median(firstPageTimes), "latePageMS": median(latePageTimes), "fullBlobReadMS": median(blobReadTimes),
      "fullBlobDecodeMS": median(blobDecodeTimes), "fullBlobTotalMS": median(blobTotalTimes)]
  }

  private static func fixtureRows(count: Int) throws -> [Data] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return try (0..<count).map { ordinal in
      let id = UUID(uuidString: String(format: "22000000-0000-4000-8000-%012d", ordinal + 1))!
      var record = Meeting(id: id, title: "記録\(ordinal) { \"引用\" } \\ パス",
        createdAt: now, duration: 27, source: .importFile, status: .ready,
        summary: "本文・空白\n改行と日付", keyPoints: ["確認"], decisions: [], openQuestions: [],
        transcript: [], privacy: RecordPrivacy(updatedAt: now))
      if ordinal == 0 {
        record.rawAudioReference = "play.m4a"
        record.originalAudioFileNames = ["part.m4a"]
        record.recordingAudioManifest = RecordingAudioManifest(recordingID: id, sampleRate: 16_000,
          parts: [.init(fileName: "part.m4a", frameOffset: 0, frameCount: 16_000, state: .finalized)])
        record.photoFileNames = ["note.jpg"]
      } else if ordinal == 1 {
        record.legacyPhotoData = [Data([0xFF, 0xD8, 0xFF, 0xD9])]
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

  private static func mediaExists(_ meeting: Meeting) -> Bool {
    let names = [meeting.rawAudioReference].compactMap { $0 } + (meeting.photoFileNames ?? [])
      + meeting.originalAudioFileNames + (meeting.recordingAudioManifest?.fileNames ?? [])
    if let manifest = meeting.recordingAudioManifest, !manifest.isValid(for: meeting.id) { return false }
    return names.allSatisfy { MediaFiles.resolve($0) != nil }
  }

  private static func mediaDigests() throws -> [SHA256.Digest] {
    try mediaNames.map { try SHA256.hash(data: Data(contentsOf: MediaFiles.root.appendingPathComponent($0))) }
  }

  private static func assertRows(_ rows: [Data], store: LocalStore, checkpoint: MeetingRowStaging.Checkpoint) throws {
    for ordinal in rows.indices {
      precondition(data(store, checkpoint.rowKey(ordinal)) == rows[ordinal])
    }
    precondition(data(store, checkpoint.rowKey(rows.count)) == nil)
  }

  private static func expectFailure<T>(_ failure: MeetingRowStaging.Failure, _ operation: () throws -> T) {
    do {
      _ = try operation()
      preconditionFailure("Expected staging refusal \(failure)")
    } catch let observed as MeetingRowStaging.Failure {
      precondition(observed == failure, "Expected \(failure), got \(observed)")
    } catch {
      preconditionFailure("Unexpected staging error \(error)")
    }
  }

  private static func saved(_ store: LocalStore) throws -> MeetingRowStaging.Checkpoint {
    try JSONDecoder().decode(MeetingRowStaging.Checkpoint.self, from: data(store, MeetingRowStaging.checkpointKey)!)
  }

  private static func open(_ name: String) throws -> LocalStore {
    let store = LocalStore(fileURL: database(name))
    try store.prepare()
    return store
  }

  private static func database(_ name: String) -> URL { MediaFiles.root.appendingPathComponent("\(name).sqlite") }

  private static func data(_ store: LocalStore, _ key: String) -> Data? {
    switch store.readOutcome(key) {
    case .data(let value): value
    case .missing: nil
    case .failed: preconditionFailure("Could not read fixture")
    }
  }

  private static func sql(_ name: String, _ statement: String) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open_v2(database(name).path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
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
