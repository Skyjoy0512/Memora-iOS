import Foundation
import Synchronization

@main
struct RecordStoreFailureChecks {
  @MainActor static func main() async throws {
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
}

// An isolated backend prevents a command-line check from touching app data.
// The production RecordStore (including its queue and failure flag) is compiled unchanged.
final class LocalStore: Sendable {
  static let shared = LocalStore()
  enum StoreError: Error { case statement(Int32) }
  enum ReadOutcome { case missing, data(Data), failed }
  private let documents = Mutex<[String: Data]>([:])
  func prepare() throws {}
  func readOutcome(_ key: String) -> ReadOutcome {
    documents.withLock { $0[key].map(ReadOutcome.data) ?? .missing }
  }
  func write(_ key: String, data: Data) throws { documents.withLock { $0[key] = data } }
  func remove(_ key: String) throws { documents.withLock { _ = $0.removeValue(forKey: key) } }
  func applyBatch(writes: [(key: String, data: Data)], removing: [String]) throws {
    documents.withLock { values in
      for (key, data) in writes { values[key] = data }
      for key in removing { values.removeValue(forKey: key) }
    }
  }
}
