import Foundation

@main
struct SourceExtractionCacheChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let calls = ExtractionCalls()
    let cache = SourceExtractionCache { url, vocabulary in
      await calls.extract(url, vocabulary: vocabulary)
    }
    let first = root.appendingPathComponent("first.txt")
    let copy = root.appendingPathComponent("copy.txt")
    try Data("取得済みの本文".utf8).write(to: first)
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
    print("SourceExtractionCacheChecks: passed (production hashing/cache; copies, changed bytes, format/vocabulary separation, retry, concurrent single flight, clear/mutation invalidation, symlink rejection; OS extraction is a fixture)")
  }
  static func expect(_ value: Bool) { precondition(value) }
}

private actor ExtractionCalls {
  var count = 0
  var empty = false
  init(empty: Bool = false) { self.empty = empty }
  func extract(_ url: URL, vocabulary: [String]) -> ProjectSourceExtractionResult {
    count += 1
    return .init(blocks: empty ? [] : [.init(text: "本文", page: 24, time: 17)], coverage: .partial,
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
