import Darwin
import Foundation

/// The OS releases this lock after a process interruption, but another live
/// extraction keeps its files protected even when it lasts beyond stale age.
final class SourceMediaStageLease: @unchecked Sendable {
  let directory: URL
  var audioURL: URL { directory.appendingPathComponent("audio.m4a") }
  private let descriptor: Int32
  private let lock = NSLock()
  private var isReleased = false

  init(directory: URL, descriptor: Int32) {
    self.directory = directory
    self.descriptor = descriptor
  }

  func remove() {
    lock.lock()
    defer { lock.unlock() }
    guard !isReleased else { return }
    isReleased = true
    try? FileManager.default.removeItem(at: directory)
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }

  deinit { remove() }
}
