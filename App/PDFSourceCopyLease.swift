import Darwin
import Foundation

/// The OS releases this lock on process death. The SQLite journal, rather than
/// deinit, decides which copied files are still provisional.
final class PDFSourceCopyLease: @unchecked Sendable {
  let id: String
  let references: [String]
  let lockURL: URL
  private let descriptor: Int32

  init(id: String, references: [String], lockURL: URL, descriptor: Int32) {
    self.id = id
    self.references = references
    self.lockURL = lockURL
    self.descriptor = descriptor
  }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
