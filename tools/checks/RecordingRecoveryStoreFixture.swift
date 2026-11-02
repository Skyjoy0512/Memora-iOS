import Foundation

// The production recovery extension owns transaction boundaries; this adapter
// supplies only encoding and the selected, temporary real SQLite store.
@MainActor
enum RecordStore {
  static var store: LocalStore!
  static var asyncCommits = 0
  static var beforeAsyncCommit: (() async -> Void)?
  static var afterAsyncCommit: (() async -> Void)?
  static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
  static func remove(_ key: String) throws { try store.remove(key) }
  static func commitAsync(writes: [(key: String, data: Data)], removing: [String]) async throws {
    let destination = store!
    asyncCommits += 1
    await beforeAsyncCommit?()
    try destination.applyBatch(writes: writes, removing: removing)
    await afterAsyncCommit?()
  }
}
