import Foundation

// Only record/formatting inputs and credential storage are fixtures. HTTP
// construction, batching, configuration checks and recovery use NotionService.
struct Meeting {
  var id = UUID()
  var title = "Fixture meeting"
  var createdAt = Date(timeIntervalSince1970: 1_700_000_000)
  var duration: TimeInterval = 60
  var source = FixtureMeetingSource()
  var summary = "Fixture summary"
  var decisions: [String] = []
  var openQuestions: [String] = []
}

struct FixtureMeetingSource { var label: String { "Fixture" } }
enum MemoraFormat { static func duration(_ value: TimeInterval) -> String { "60s" } }
enum KeychainStore {
  static func set(_ value: String?, forKey key: String) -> Bool { false }
  static func string(forKey key: String) -> String? {
    preconditionFailure("Host checks must never read real credentials")
  }
}

final class NotionFixtureConfiguration: @unchecked Sendable {
  private let lock = NSLock()
  private var value: NotionSaveConfiguration?

  init(_ value: NotionSaveConfiguration?) { self.value = value }

  func read() -> NotionSaveConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func replace(_ value: NotionSaveConfiguration?) {
    lock.lock()
    defer { lock.unlock() }
    self.value = value
  }
}
