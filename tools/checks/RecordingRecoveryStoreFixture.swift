import Foundation

// The production recovery extension owns transaction boundaries; this adapter
// supplies only encoding and the selected, temporary real SQLite store.
@MainActor
enum RecordStore {
  static var store: LocalStore!
  static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
  static func remove(_ key: String) throws { try store.remove(key) }
}
