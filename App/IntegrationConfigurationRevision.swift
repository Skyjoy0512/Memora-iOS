import Foundation

/// Detects settings A → B → A without persisting an execution grant.
final class IntegrationConfigurationRevision: @unchecked Sendable {
  private let lock = NSLock()
  private var revision = UUID()

  func current() -> UUID {
    lock.lock()
    defer { lock.unlock() }
    return revision
  }

  func invalidate() {
    lock.lock()
    defer { lock.unlock() }
    revision = UUID()
  }
}
