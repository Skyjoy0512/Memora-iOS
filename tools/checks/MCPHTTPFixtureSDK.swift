import Foundation

// Host checks exercise the production actor, not a replacement transport.
// Only SDK protocol/logging symbols and keychain storage are fixture-owned;
// Bitrig builds separately check conformance to the real pinned MCP SDK.
protocol Transport: Actor {
  func connect() async throws
  func disconnect() async
  func send(_ data: Data) async throws
  func receive() async -> AsyncThrowingStream<Data, Error>
}
enum MCP { enum Version { static let latest = "2025-11-25" } }
struct SwiftLogNoOpLogHandler: Sendable {}
struct Logger: Sendable {
  init(label: String, factory: (String) -> SwiftLogNoOpLogHandler) {}
}

enum KeychainStore {
  private static let memory = FixtureKeychain()
  static func string(forKey key: String) -> String? { memory.read(key) }
  static func replaceIfUnchanged(_ value: String, expected: String, forKey key: String) -> Bool {
    memory.replace(value, expected: expected, key: key)
  }
  static func seed(_ value: String?, forKey key: String) { memory.seed(value, key: key) }
}

private final class FixtureKeychain: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  func read(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[key] }
  func seed(_ value: String?, key: String) { lock.lock(); defer { lock.unlock() }; values[key] = value }
  func replace(_ value: String, expected: String, key: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard values[key] == expected else { return false }
    values[key] = value; return true
  }
}
