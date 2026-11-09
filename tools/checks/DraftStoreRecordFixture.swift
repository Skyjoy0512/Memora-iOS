import Foundation

// SQLite and the draft codec are real. This boundary performs synchronous
// writes; it does not prove RecordStore's background queue ordering.
@MainActor enum RecordStore {
  static var store: LocalStore!
  static var failsReading = false
  enum LoadOutcome { case absent, failed; case data(Data) }
  static func load(_ key: String) -> LoadOutcome {
    guard !failsReading else { return .failed }
    switch store.readOutcome(key) {
    case .missing: return .absent
    case .failed: return .failed
    case .data(let data): return .data(data)
    }
  }
  static func loadLatestData(_ key: String) -> LoadOutcome { load(key) }
  static func saveData(_ data: Data, key: String, onFailure: (@MainActor () -> Void)? = nil) {
    do { try store.write(key, data: data) } catch { onFailure?() }
  }
  static func saveDataNow(_ data: Data, key: String) throws { try store.write(key, data: data) }
  static func remove(_ key: String) throws { try store.applyBatch(writes: [], removing: [key]) }
  static func remove(_ key: String, ifMatching matches: @Sendable (Data) -> Bool) throws {
    guard case .data(let data) = store.readOutcome(key), matches(data) else { return }
    try remove(key)
  }
}
