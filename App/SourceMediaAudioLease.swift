import Foundation

/// A prepared chunk remains readable until recognition settles. Unconsumed
/// lookahead results also release their file when a task group is cancelled.
final class SourceMediaAudioLease: @unchecked Sendable {
  let url: URL
  private let lock = NSLock()
  private var removed = false

  init(url: URL) { self.url = url }

  func remove() {
    lock.lock()
    defer { lock.unlock() }
    guard !removed else { return }
    removed = true
    try? FileManager.default.removeItem(at: url)
  }

  deinit { remove() }
}
