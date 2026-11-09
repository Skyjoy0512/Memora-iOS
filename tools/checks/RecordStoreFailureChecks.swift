import Foundation
import Synchronization

@main
struct RecordStoreFailureChecks {
  @MainActor static func main() async throws {
    try await draftQueueChecks()
    try RecordStore.saveNow("original", key: "record")
    try RecordStore.saveNow("draft", key: "draft")
    RecordStore.setFailureInjection(true)
    do {
      try await RecordStore.commitAsync(writes: [("record", Data("changed".utf8))], removing: ["draft"])
      preconditionFailure("Injected async failure reported success")
    } catch {}
    guard case .data(let original) = RecordStore.load("record"),
          case .data = RecordStore.load("draft") else {
      preconditionFailure("Failed async transaction changed existing values")
    }
    let originalValue = try JSONDecoder().decode(String.self, from: original)
    precondition(originalValue == "original")

    // Both requests run through the production queue; exactly one must fail.
    RecordStore.setFailureInjection(true)
    let first = Task { @MainActor in
      do { try await RecordStore.commitAsync(writes: [("first", Data("value".utf8))], removing: []); return true }
      catch { return false }
    }
    let second = Task { @MainActor in
      do { try await RecordStore.commitAsync(writes: [("second", Data("value".utf8))], removing: []); return true }
      catch { return false }
    }
    let results = await [first.value, second.value]
    precondition(results.filter { !$0 }.count == 1)
    try RecordStore.saveNow("recovered", key: "record")
    guard case .data(let recovered) = RecordStore.load("record") else { preconditionFailure() }
    let recoveredValue = try JSONDecoder().decode(String.self, from: recovered)
    precondition(recoveredValue == "recovered")
    let key = "editor.check"
    try DraftStore.saveAndWait("保存した本文", key: key)
    DraftStore.save("次の編集中の本文", key: key)
    DraftStore.clear(key, matching: "保存した本文")
    precondition(DraftStore.read(key) == .text("次の編集中の本文"), "A late completion erased a newer queued draft")
    DraftStore.clear(key, matching: "次の編集中の本文")
    precondition(DraftStore.read(key) == .absent)
    try RecordStore.saveDataNow(JSONEncoder().encode("旧形式"), key: DraftStore.storageKey(for: key))
    DraftStore.clear(key, matching: "旧形式")
    precondition(DraftStore.read(key) == .absent)
    let invalid = Data([1, 255])
    try RecordStore.saveDataNow(invalid, key: DraftStore.storageKey(for: key))
    precondition(DraftStore.read(key) == .unreadable)
    do {
      _ = try DraftStore.readAll(["absent.field", key])
      preconditionFailure("Unreadable field admitted a partially restored editor")
    } catch DraftStore.Failure.unreadable {}
    do {
      try DraftStore.saveAndWait("replacement", key: key)
      preconditionFailure("Unreadable draft was overwritten")
    } catch DraftStore.Failure.unreadable {}
    DraftStore.save("replacement", key: key)
    DraftStore.clear(key)
    DraftStore.clear(key, matching: "replacement")
    await RecordStore.flushAsync()
    guard case .data(let retained) = RecordStore.load(DraftStore.storageKey(for: key)) else { preconditionFailure("Unreadable draft was deleted") }
    precondition(retained == invalid)
    print("DraftStore checks: newer queued draft retention, matching clear, legacy clear, partial restore refusal and unreadable-byte protection passed")
    print("RecordStoreFailureChecks: passed (async rollback, concurrent one-shot failure, sync recovery)")
  }

  @MainActor static func draftQueueChecks() async throws {
    let key = "queue.editor"
    let storageKey = DraftStore.storageKey(for: key)
    try DraftStore.saveAndWait("以前の本文", key: key)
    let first = QueueGateValue()
    RecordStore.save(first, key: "unrelated.large.write")
    await first.entered()
    DraftStore.save("入力した直後の本文", key: key)
    precondition(DraftStore.read(key) == .text("入力した直後の本文"))
    guard case .data(let committed) = RecordStore.load(storageKey) else { preconditionFailure() }
    precondition(committed != Data([1]) + Data("入力した直後の本文".utf8), "The queue was not actually blocked")
    first.release.signal()
    await RecordStore.flushAsync()
    precondition(DraftStore.read(key) == .text("入力した直後の本文"))

    // A synchronous business commit that settles a draft must invalidate it
    // before its delayed write acknowledgement can run on the main actor.
    DraftStore.save("保存する本文", key: key)
    try RecordStore.commitNow(writes: [("business.record", Data("saved".utf8))], removing: [storageKey])
    precondition(DraftStore.read(key) == .absent)
    await Task.yield()
    precondition(DraftStore.read(key) == .absent)

    // Completion of an earlier async commit must leave a newer queued draft.
    try DraftStore.saveAndWait("先の編集", key: key)
    let beforeCommit = QueueGateValue()
    RecordStore.save(beforeCommit, key: "before.commit")
    await beforeCommit.entered()
    var started = false
    let commit = Task { @MainActor in
      started = true
      try await RecordStore.commitAsync(writes: [], removing: [storageKey])
    }
    while !started { await Task.yield() }
    let afterCommit = QueueGateValue()
    RecordStore.save(afterCommit, key: "after.commit")
    DraftStore.save("次の編集", key: key)
    beforeCommit.release.signal()
    await afterCommit.entered()
    try await commit.value
    precondition(DraftStore.read(key) == .text("次の編集"))
    afterCommit.release.signal()
    await RecordStore.flushAsync()

    // Preserve input after an actual backend write failure, report once, and
    // keep that volatile value distinct from the unchanged committed bytes.
    let failures = Mutex(0)
    let observer = NotificationCenter.default.addObserver(forName: LocalSaveFailure.notification, object: nil, queue: nil) { _ in
      failures.withLock { $0 += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    LocalStore.shared.failWrites.withLock { _ = $0.insert(storageKey) }
    DraftStore.save("まだ保存できていない本文", key: key)
    await RecordStore.flushAsync()
    for _ in 0..<1000 {
      if failures.withLock({ $0 }) > 0 { break }
      await Task.yield()
    }
    precondition(failures.withLock { $0 } == 1, "Failed draft write was not reported")
    precondition(DraftStore.read(key) == .text("まだ保存できていない本文"))
    guard case .data(let old) = RecordStore.load(storageKey) else { preconditionFailure() }
    precondition(old == Data([1]) + Data("次の編集".utf8))
    LocalStore.shared.failWrites.withLock { _ = $0.remove(storageKey) }
    DraftStore.clear(key, matching: "次の編集")
    precondition(DraftStore.read(key) == .text("まだ保存できていない本文"), "Old success erased newer unsaved input")
    try DraftStore.saveAndWait("まだ保存できていない本文", key: key)
    guard case .data(let saved) = RecordStore.load(storageKey) else { preconditionFailure() }
    precondition(saved == Data([1]) + Data("まだ保存できていない本文".utf8))
    DraftStore.clear(key, matching: "まだ保存できていない本文")
    precondition(DraftStore.read(key) == .absent && failures.withLock { $0 } == 1)
    print("PASS: production draft queue ordering, immediate reopen behind a blocked encode, sync/async transaction settlement, failed-write input retention/report/retry; isolated backend, no app data")
  }
}

// An isolated backend prevents a command-line check from touching app data.
// The production RecordStore (including its queue and failure flag) is compiled unchanged.
final class LocalStore: Sendable {
  static let shared = LocalStore()
  enum StoreError: Error { case statement(Int32) }
  enum ReadOutcome { case missing, data(Data), failed }
  private let documents = Mutex<[String: Data]>([:])
  let failWrites = Mutex<Set<String>>([])
  func prepare() throws {}
  func readOutcome(_ key: String) -> ReadOutcome {
    documents.withLock { $0[key].map(ReadOutcome.data) ?? .missing }
  }
  func write(_ key: String, data: Data) throws {
    if failWrites.withLock({ $0.contains(key) }) { throw StoreError.statement(1) }
    documents.withLock { $0[key] = data }
  }
  func remove(_ key: String) throws { documents.withLock { _ = $0.removeValue(forKey: key) } }
  func applyBatch(writes: [(key: String, data: Data)], removing: [String]) throws {
    documents.withLock { values in
      for (key, data) in writes { values[key] = data }
      for key in removing { values.removeValue(forKey: key) }
    }
  }
}

final class QueueGateValue: Encodable, Sendable {
  let started = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  func encode(to encoder: Encoder) throws {
    started.signal()
    precondition(release.wait(timeout: .now() + 15) == .success, "Queue gate was not released")
    var value = encoder.singleValueContainer()
    try value.encode("unrelated value")
  }
  func entered() async {
    let entered = await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: self.started.wait(timeout: .now() + 15) == .success)
      }
    }
    precondition(entered, "Queue gate did not start")
  }
}
