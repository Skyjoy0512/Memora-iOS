import Darwin
import Foundation

/// Kept alive by the receipt, including copies passed between tasks. The OS
/// releases flock after a crash, allowing a later preparation to recover space.
final class PDFSourcePartitionLease: @unchecked Sendable {
  let directory: URL
  private let descriptor: Int32
  private let lock = NSLock()
  private var isReleased = false

  init(directory: URL, descriptor: Int32) {
    self.directory = directory
    self.descriptor = descriptor
  }

  func finishPreparation(outputBytes: Int) throws {
    lock.lock()
    defer { lock.unlock() }
    guard !isReleased, outputBytes >= 0, outputBytes <= PDFSourcePartition.maximumOutputBytes else {
      throw PDFSourcePartitionFailure.stagingLimit
    }
    // Once the immutable input has been removed, release its unused reservation
    // while retaining the live OS lease for the returned parts.
    try Data(String(outputBytes + 4_096).utf8).write(to: directory.appendingPathComponent(".reservation"), options: .atomic)
  }

  @discardableResult
  func remove() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !isReleased else { return !FileManager.default.fileExists(atPath: directory.path) }
    var removed = false
    do { try FileManager.default.removeItem(at: directory); removed = true }
    catch { removed = !FileManager.default.fileExists(atPath: directory.path) }
    if !isReleased {
      isReleased = true
      flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    return removed
  }

  deinit { remove() }
}
