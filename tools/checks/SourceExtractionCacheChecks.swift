import Foundation
import SQLite3
import CryptoKit

@main
struct SourceExtractionCacheChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try SourceMediaCheckpointChecks.run(root: root)
    try await RecordedAudioTranscriptionChecks.run(root: root)
    try await speechLocaleChecks(root: root)
    let calls = ExtractionCalls()
    let cache = SourceExtractionCache { url, vocabulary in
      await calls.extract(url, vocabulary: vocabulary)
    }
    let first = root.appendingPathComponent("first.txt")
    let copy = root.appendingPathComponent("copy.txt")
    try Data("取得済みの本文".utf8).write(to: first)
    let resumeCalls = PDFResumeCalls()
    let resumeDirectory = root.appendingPathComponent("resume-result-cache")
    let partialCache = SourceExtractionCache(persistenceDirectory: resumeDirectory) { _, _ in await resumeCalls.extract() }
    let partial = try await partialCache.extract(first)
    precondition(partial.resumePage == 2)
    let restartedResume = SourceExtractionCache(persistenceDirectory: resumeDirectory) { _, _ in await resumeCalls.extract() }
    let completed = try await restartedResume.extract(first)
    precondition(completed.resumePage == nil)
    expect(await resumeCalls.count == 2)
    let completedCache = SourceExtractionCache(persistenceDirectory: resumeDirectory) { _, _ in
      preconditionFailure("Completed result was not reused")
    }
    _ = try await completedCache.extract(first)
    try FileManager.default.copyItem(at: first, to: copy)
    let initial = try await cache.extract(first)
    let reused = try await cache.extract(copy, vocabulary: ["文章の解析には無関係"])
    precondition(initial.blocks == reused.blocks && reused.pageCount == 24 && reused.unreadablePages == [3]
      && reused.omittedPages == [23] && reused.ocrPages == [24] && reused.coverage == .partial)
    expect(await calls.count == 1)
    // Same length and modification date are insufficient to identify evidence.
    let modified = try copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
    try Data("異なる資料本文".utf8).write(to: copy)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: copy.path)
    _ = try await cache.extract(copy)
    expect(await calls.count == 2)
    let differentFormat = root.appendingPathComponent("same-bytes.md")
    try FileManager.default.copyItem(at: first, to: differentFormat)
    _ = try await cache.extract(differentFormat)
    expect(await calls.count == 3)
    let audio = root.appendingPathComponent("voice.m4a")
    try FileManager.default.copyItem(at: first, to: audio)
    _ = try await cache.extract(audio, vocabulary: ["Memora"])
    _ = try await cache.extract(audio, vocabulary: ["Memora"])
    _ = try await cache.extract(audio, vocabulary: ["別の用語"])
    expect(await calls.count == 5)

    let failures = ExtractionCalls(empty: true)
    let retry = SourceExtractionCache { url, terms in await failures.extract(url, vocabulary: terms) }
    _ = try await retry.extract(first)
    _ = try await retry.extract(first)
    expect(await failures.count == 2)

    let gate = ExtractionGate()
    let shared = SourceExtractionCache { _, _ in await gate.wait() }
    let one = Task { try await shared.extract(first) }
    await gate.entered()
    let two = Task { try await shared.extract(copy) }
    // Different bytes must never join an in-flight request.
    await gate.waitForCount(2)
    await gate.resume()
    _ = try await one.value
    _ = try await two.value
    expect(await gate.count == 2)

    let identicalGate = ExtractionGate()
    let single = SourceExtractionCache { _, _ in await identicalGate.wait() }
    let a = Task { try await single.extract(first) }
    await identicalGate.entered()
    let b = Task { try await single.extract(first) }
    for _ in 0..<100 { await Task.yield() }
    await identicalGate.resume()
    _ = try await a.value
    _ = try await b.value
    expect(await identicalGate.count == 1)

    let invalidationGate = ExtractionGate()
    let invalidation = SourceExtractionCache { _, _ in await invalidationGate.wait() }
    let pending = Task { try await invalidation.extract(first) }
    await invalidationGate.entered()
    await invalidation.clear()
    await invalidationGate.resume()
    do { _ = try await pending.value; preconditionFailure("Cleared job published content") }
    catch is CancellationError {} catch ProjectSourceFiles.Failure.invalidFile {}
    _ = try await invalidation.extract(first)
    expect(await invalidationGate.count == 2)

    let mutationGate = ExtractionGate()
    let mutable = SourceExtractionCache { _, _ in await mutationGate.wait() }
    let changing = Task { try await mutable.extract(copy) }
    await mutationGate.entered()
    try Data("解析中に変更した本文".utf8).write(to: copy)
    await mutationGate.resume()
    do { _ = try await changing.value; preconditionFailure("Changed evidence was cached") }
    catch ProjectSourceFiles.Failure.invalidFile {}

    let link = root.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
    do { _ = try await cache.extract(link); preconditionFailure("Symlink accepted") }
    catch ProjectSourceFiles.Failure.invalidFile {}
    try await durableChecks(root: root, original: first)
    try await pdfVersionChecks(root: root)
    print("SourceExtractionCacheChecks: passed (production hashing/SQLite cache; restart, copied originals, coverage/thumbnail retention, expiry, eviction, corrupt records, missing thumbnails, unavailable persistence, retry, concurrent single flight, clear/mutation invalidation, symlink rejection; OS extraction is a fixture)")
  }

  static func pdfVersionChecks(root: URL) async throws {
    let directory = root.appendingPathComponent("pdf-extractor-version", isDirectory: true)
    let pdf = root.appendingPathComponent("versioned.pdf")
    let text = root.appendingPathComponent("versioned.txt")
    let content = Data("same accessible original".utf8)
    try content.write(to: pdf)
    try content.write(to: text)
    let digest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
    let vocabulary = SHA256.hash(data: try JSONEncoder().encode([String]())).map { String(format: "%02x", $0) }.joined()
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let prefix = "v2.\(os.majorVersion).\(os.minorVersion).\(Locale.current.identifier).\(digest)."
    let previous = SourceExtractionPersistence(directory: directory)
    previous.write(prefix + "pdf." + vocabulary, result: .init(blocks: [.init(text: "old digital-only PDF")]))
    previous.write(prefix + "txt." + vocabulary, result: .init(blocks: [.init(text: "old unchanged text")]))
    let calls = ExtractionCalls()
    let updated = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await calls.extract(url, vocabulary: terms)
    }
    let newPDF = try await updated.extract(pdf)
    expect(await calls.count == 1)
    precondition(newPDF.blocks.first?.text == "本文")
    let unchanged = try await updated.extract(text)
    precondition(unchanged.blocks.first?.text == "old unchanged text")
    expect(await calls.count == 1)
    let restarted = SourceExtractionCache(persistenceDirectory: directory) { _, _ in
      preconditionFailure("New PDF extraction was not reused after restart")
    }
    let reused = try await restarted.extract(pdf)
    precondition(reused.blocks == newPDF.blocks)
    let failureDirectory = root.appendingPathComponent("failed-ocr-result")
    let failureCalls = OCRFailureCalls()
    let failed = SourceExtractionCache(persistenceDirectory: failureDirectory) { _, _ in await failureCalls.extract() }
    _ = try await failed.extract(pdf)
    _ = try await failed.extract(pdf)
    expect(await failureCalls.count == 2)
    let retry = SourceExtractionCache(persistenceDirectory: failureDirectory) { _, _ in await failureCalls.extract() }
    _ = try await retry.extract(pdf)
    expect(await failureCalls.count == 3)
    print("PDF cache version: PASS. Old PDF extraction ignored, unrelated text cache retained, new PDF result reused. Extractor fixture; production hash/SQLite cache.")
  }

  static func durableChecks(root: URL, original: URL) async throws {
    let directory = root.appendingPathComponent("durable", isDirectory: true)
    let calls = ExtractionCalls()
    let cache = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await calls.extract(url, vocabulary: terms)
    }
    let first = try await cache.extract(original)
    expect(await calls.count == 1)
    let restartCalls = ExtractionCalls()
    let restarted = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await restartCalls.extract(url, vocabulary: terms)
    }
    let restored = try await restarted.extract(original)
    precondition(restored.blocks == first.blocks && restored.thumbnail == first.thumbnail
      && restored.notice == first.notice && restored.coverage == first.coverage
      && restored.pageCount == first.pageCount && restored.unreadablePages == first.unreadablePages
      && restored.omittedPages == first.omittedPages && restored.ocrPages == first.ocrPages)
    expect(await restartCalls.count == 0)

    // A cache never grants access in the absence of the original.
    let nonexistent = root.appendingPathComponent("deleted.txt")
    do { _ = try await restarted.extract(nonexistent); preconditionFailure("Read without an original") }
    catch {}
    expect(await restartCalls.count == 0)

    // Disk reuse keeps format and speech vocabulary identities after relaunch.
    let renamed = root.appendingPathComponent("relaunch-copy.txt")
    try FileManager.default.copyItem(at: original, to: renamed)
    _ = try await restarted.extract(renamed)
    expect(await restartCalls.count == 0)
    let audio = root.appendingPathComponent("relaunch-audio.m4a")
    try FileManager.default.copyItem(at: original, to: audio)
    _ = try await cache.extract(audio, vocabulary: ["固有名詞"])
    let audioRestart = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await restartCalls.extract(url, vocabulary: terms)
    }
    _ = try await audioRestart.extract(audio, vocabulary: ["固有名詞"])
    expect(await restartCalls.count == 0)
    _ = try await audioRestart.extract(audio, vocabulary: ["別の用語"])
    expect(await restartCalls.count == 1)

    // A corrupt derived record is discarded; the original is extracted again.
    try execute("UPDATE extractions SET data = X'7B7D';", directory: directory)
    let corruptRestart = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await restartCalls.extract(url, vocabulary: terms)
    }
    _ = try await corruptRestart.extract(original)
    expect(await restartCalls.count == 2)
    for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where url.pathExtension == "thumb" { try FileManager.default.removeItem(at: url) }
    let missingThumbnail = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await restartCalls.extract(url, vocabulary: terms)
    }
    _ = try await missingThumbnail.extract(original)
    expect(await restartCalls.count == 3)

    await missingThumbnail.clear()
    let afterClear = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await restartCalls.extract(url, vocabulary: terms)
    }
    _ = try await afterClear.extract(original)
    expect(await restartCalls.count == 4)

    let expiryDirectory = root.appendingPathComponent("expiry", isDirectory: true)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let expiryCalls = ExtractionCalls()
    let expiring = SourceExtractionCache(persistenceDirectory: expiryDirectory, now: { start }) { url, terms in
      await expiryCalls.extract(url, vocabulary: terms)
    }
    _ = try await expiring.extract(original)
    let later = start.addingTimeInterval(SourceExtractionPersistence.retention + 1)
    let expired = SourceExtractionCache(persistenceDirectory: expiryDirectory, now: { later }) { url, terms in
      await expiryCalls.extract(url, vocabulary: terms)
    }
    _ = try await expired.extract(original)
    expect(await expiryCalls.count == 2)

    let evictionDirectory = root.appendingPathComponent("eviction", isDirectory: true)
    let evictionCalls = ExtractionCalls()
    let eviction = SourceExtractionCache(persistenceDirectory: evictionDirectory) { url, terms in
      await evictionCalls.extract(url, vocabulary: terms)
    }
    for index in 0...SourceExtractionPersistence.maximumEntries {
      let file = root.appendingPathComponent("entry-\(index).txt")
      try Data("独立した資料 \(index)".utf8).write(to: file)
      _ = try await eviction.extract(file)
    }
    let evictionRestart = SourceExtractionCache(persistenceDirectory: evictionDirectory) { url, terms in
      await evictionCalls.extract(url, vocabulary: terms)
    }
    _ = try await evictionRestart.extract(root.appendingPathComponent("entry-0.txt"))
    expect(await evictionCalls.count == SourceExtractionPersistence.maximumEntries + 2)

    let byteDirectory = root.appendingPathComponent("byte-budget", isDirectory: true)
    let byteBudget = SourceExtractionCache(persistenceDirectory: byteDirectory) { _, _ in
      .init(blocks: [.init(text: String(repeating: "a", count: 6 * 1024 * 1024))])
    }
    for index in 0..<6 {
      _ = try await byteBudget.extract(root.appendingPathComponent("entry-\(index).txt"))
    }
    let storedBytes = try integer("SELECT SUM(bytes) FROM extractions;", directory: byteDirectory)
    precondition(storedBytes <= SourceExtractionPersistence.maximumBytes && storedBytes > 0)
    let retainedCount = try integer("SELECT COUNT(*) FROM extractions;", directory: byteDirectory)
    precondition(retainedCount == 5)

    let blocked = root.appendingPathComponent("unavailable-cache")
    try Data("ディレクトリではない".utf8).write(to: blocked)
    let unavailable = SourceExtractionCache(persistenceDirectory: blocked) { url, terms in
      await restartCalls.extract(url, vocabulary: terms)
    }
    _ = try await unavailable.extract(original)
    expect(await restartCalls.count == 5)

    let failures = ExtractionCalls(empty: true)
    let failureDirectory = root.appendingPathComponent("failures", isDirectory: true)
    let failure = SourceExtractionCache(persistenceDirectory: failureDirectory) { url, terms in
      await failures.extract(url, vocabulary: terms)
    }
    _ = try await failure.extract(original)
    let failureRestart = SourceExtractionCache(persistenceDirectory: failureDirectory) { url, terms in
      await failures.extract(url, vocabulary: terms)
    }
    _ = try await failureRestart.extract(original)
    expect(await failures.count == 2)

    let pendingDirectory = root.appendingPathComponent("pending", isDirectory: true)
    let gate = ExtractionGate()
    let pendingCache = SourceExtractionCache(persistenceDirectory: pendingDirectory) { _, _ in await gate.wait() }
    let pending = Task { try await pendingCache.extract(original) }
    await gate.entered()
    await pendingCache.clear()
    await gate.resume()
    do { _ = try await pending.value; preconditionFailure("Cleared result persisted") }
    catch is CancellationError {} catch ProjectSourceFiles.Failure.invalidFile {}
    let pendingRestart = SourceExtractionCache(persistenceDirectory: pendingDirectory) { url, terms in
      await restartCalls.extract(url, vocabulary: terms)
    }
    _ = try await pendingRestart.extract(original)
    expect(await restartCalls.count == 6)

    try await invalidationChecks(root: root, original: original)
  }

  static func speechLocaleChecks(root: URL) async throws {
    let defaults = UserDefaults.standard
    let previous = defaults.object(forKey: "memora.transcriptionLanguage")
    defer {
      if let previous { defaults.set(previous, forKey: "memora.transcriptionLanguage") }
      else { defaults.removeObject(forKey: "memora.transcriptionLanguage") }
    }
    let calls = ExtractionCalls()
    let file = root.appendingPathComponent("locale-fixture.m4a")
    let data = Data("media identity fixture, not actual speech".utf8)
    try data.write(to: file)
    let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let checkpoints = SourceMediaCheckpointStore(directory: root.appendingPathComponent("locale-checkpoints"))
    let key = try SourceMediaCheckpointStore.key(fingerprint: fingerprint, suffix: "m4a",
      locale: Locale(identifier: "ja-JP"), vocabulary: [])
    let session = checkpoints.begin()
    let prefix = SourceMediaCheckpoint(duration: 1_801, completedChunks: 1, blocks: [])
    checkpoints.save(prefix, key: key, session: session)
    let cache = SourceExtractionCache(mediaExtraction: { url, vocabulary, locale in
      UserDefaults.standard.set("english", forKey: "memora.transcriptionLanguage")
      var result = await calls.extract(url, vocabulary: vocabulary)
      result.notice = locale.identifier
      return result
    }, discardMediaCheckpoints: { fingerprints in
      if let fingerprints { checkpoints.invalidate(fingerprints: fingerprints) }
      else { checkpoints.clear() }
    }) { _, _ in preconditionFailure("Media must receive its captured locale") }
    defaults.set("japanese", forKey: "memora.transcriptionLanguage")
    let japanese = try await cache.extract(file)
    let english = try await cache.extract(file)
    defaults.set("japanese", forKey: "memora.transcriptionLanguage")
    let cachedJapanese = try await cache.extract(file)
    precondition(japanese.notice == "ja-JP" && english.notice == "en-US" && cachedJapanese.notice == "ja-JP")
    expect(await calls.count == 2)
    await cache.invalidate(fingerprints: [fingerprint])
    checkpoints.save(prefix, key: key, session: session)
    precondition(checkpoints.load(key, duration: 1_801, session: checkpoints.begin()) == nil)
    let next = checkpoints.begin()
    checkpoints.save(prefix, key: key, session: next)
    await cache.clearStoredResults()
    checkpoints.save(prefix, key: key, session: next)
    precondition(checkpoints.load(key, duration: 1_801, session: checkpoints.begin()) == nil)
  }

  static func invalidationChecks(root: URL, original: URL) async throws {
    let fingerprint = SHA256.hash(data: try Data(contentsOf: original)).map { String(format: "%02x", $0) }.joined()
    let directory = root.appendingPathComponent("selective-invalidation", isDirectory: true)
    let calls = ExtractionCalls()
    let cache = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await calls.extract(url, vocabulary: terms)
    }
    let unrelated = root.appendingPathComponent("entry-0.txt")
    let audio = root.appendingPathComponent("relaunch-audio.m4a")
    _ = try await cache.extract(original)
    _ = try await cache.extract(audio, vocabulary: ["固有名詞"])
    _ = try await cache.extract(unrelated)
    await cache.invalidate(fingerprints: [fingerprint])
    let retained = try integer("SELECT COUNT(*) FROM extractions;", directory: directory)
    precondition(retained == 1)
    _ = try await cache.extract(unrelated)
    expect(await calls.count == 3)
    _ = try await cache.extract(original)
    expect(await calls.count == 4)
    // Both disk variants are gone; unrelated evidence is retained.
    let restart = SourceExtractionCache(persistenceDirectory: directory) { url, terms in
      await calls.extract(url, vocabulary: terms)
    }
    _ = try await restart.extract(unrelated)
    expect(await calls.count == 4)
    _ = try await restart.extract(original)
    expect(await calls.count == 4)
    _ = try await restart.extract(audio, vocabulary: ["固有名詞"])
    expect(await calls.count == 5)

    let pendingDirectory = root.appendingPathComponent("pending-selective", isDirectory: true)
    let gate = ExtractionGate()
    let pendingCache = SourceExtractionCache(persistenceDirectory: pendingDirectory) { _, _ in await gate.wait() }
    let pending = Task { try await pendingCache.extract(original) }
    await gate.entered()
    let shared = Task { try await pendingCache.extract(original) }
    for _ in 0..<100 { await Task.yield() }
    await pendingCache.invalidate(fingerprints: [fingerprint])
    await gate.resume()
    for task in [pending, shared] {
      do { _ = try await task.value; preconditionFailure("Deleted evidence was published") }
      catch is CancellationError {} catch ProjectSourceFiles.Failure.invalidFile {}
    }
    let afterDeletion = SourceExtractionCache(persistenceDirectory: pendingDirectory) { url, terms in
      await calls.extract(url, vocabulary: terms)
    }
    _ = try await afterDeletion.extract(original)
    expect(await calls.count == 6)

    let singleDirectory = root.appendingPathComponent("single-publication", isDirectory: true)
    let bootstrap = SourceExtractionPersistence(directory: singleDirectory)
    _ = bootstrap.read("not-stored")
    try execute("CREATE TABLE publications (value INTEGER); CREATE TRIGGER count_publications AFTER INSERT ON extractions BEGIN INSERT INTO publications VALUES (1); END;", directory: singleDirectory)
    let singleGate = ExtractionGate()
    let single = SourceExtractionCache(persistenceDirectory: singleDirectory) { _, _ in await singleGate.wait() }
    let a = Task { try await single.extract(original) }
    await singleGate.entered()
    let b = Task { try await single.extract(original) }
    for _ in 0..<100 { await Task.yield() }
    // Legacy-record deletion must not cancel another live import.
    await single.clearStoredResults()
    await singleGate.resume()
    _ = try await a.value
    _ = try await b.value
    let publications = try integer("SELECT COUNT(*) FROM publications;", directory: singleDirectory)
    precondition(publications == 1)
  }

  static func execute(_ sql: String, directory: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(directory.appendingPathComponent("extractions.sqlite").path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
  }

  static func integer(_ sql: String, directory: URL) throws -> Int {
    var db: OpaquePointer?
    precondition(sqlite3_open(directory.appendingPathComponent("extractions.sqlite").path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var query: OpaquePointer?
    precondition(sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK)
    defer { sqlite3_finalize(query) }
    precondition(sqlite3_step(query) == SQLITE_ROW)
    return Int(sqlite3_column_int64(query, 0))
  }
  static func expect(_ value: Bool) { precondition(value) }
}

private actor OCRFailureCalls {
  var count = 0
  func extract() -> ProjectSourceExtractionResult {
    count += 1
    return .init(blocks: [.init(text: "preserved digital text", page: 1)], coverage: .partial,
      pageCount: 1, ocrPages: [1], ocrFailedPages: [1])
  }
}

private actor ExtractionCalls {
  var count = 0
  var empty = false
  init(empty: Bool = false) { self.empty = empty }
  func extract(_ url: URL, vocabulary: [String]) -> ProjectSourceExtractionResult {
    count += 1
    return .init(blocks: empty ? [] : [.init(text: "本文", page: 24, time: 17)], thumbnail: Data([0, 1, 2]),
      notice: "読み取れないページがあります", coverage: .partial,
      pageCount: 24, unreadablePages: [3], omittedPages: [23], ocrPages: [24])
  }
}

private actor ExtractionGate {
  var count = 0
  var continuations: [CheckedContinuation<ProjectSourceExtractionResult, Never>] = []
  var released = false
  func wait() async -> ProjectSourceExtractionResult {
    count += 1
    if released { return .init(blocks: [.init(text: "本文")]) }
    return await withCheckedContinuation { continuations.append($0) }
  }
  func entered() async { await waitForCount(1) }
  func waitForCount(_ expected: Int) async {
    for _ in 0..<10_000 { if count >= expected { return }; await Task.yield() }
    preconditionFailure("Extraction never reached boundary")
  }
  func resume() {
    released = true
    let pending = continuations
    continuations = []
    for continuation in pending { continuation.resume(returning: .init(blocks: [.init(text: "本文")])) }
  }
}

private actor PDFResumeCalls {
  var count = 0
  func extract() -> ProjectSourceExtractionResult {
    count += 1
    return .init(blocks: [.init(text: "preserved page", page: 1)], coverage: count == 1 ? .partial : .complete,
      pageCount: 2, omittedPages: count == 1 ? [2] : [], resumePage: count == 1 ? 2 : nil)
  }
}
