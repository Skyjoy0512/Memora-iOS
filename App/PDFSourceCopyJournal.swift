import Darwin
import Foundation

/// Only files reserved by this journal can be reclaimed. Old workspace files,
/// company templates and other workspaces are never swept by filename or age.
@MainActor
struct PDFSourceCopyJournal {
  static let key = "memora.pendingPDFSourceCopies.v1"
  var store: LocalStore
  var directory: URL = ProjectSourceFiles.directory

  func begin(count: Int) throws -> PDFSourceCopyLease {
    guard (1...100).contains(count) else { throw ProjectSourceFiles.Failure.invalidFile }
    var entries = try load()
    guard entries.count < 256 else { throw ProjectSourceFiles.Failure.capacity }
    let id = UUID().uuidString
    let references = (1...count).map { "pdfcopy-\(id)-\($0).pdf" }
    guard let lease = try acquire(id: id, references: references) else { throw ProjectSourceFiles.Failure.invalidFile }
    do {
      entries[id] = references
      try store.write(Self.key, data: JSONEncoder().encode(entries))
      return lease
    } catch {
      try? FileManager.default.removeItem(at: lease.lockURL)
      throw error
    }
  }

  /// This payload must land in the same SQLite transaction as the new sources.
  /// A crash then sees either all provisional names or only unused copies.
  func committedDocument(_ lease: PDFSourceCopyLease, retaining references: Set<String>) throws -> (key: String, data: Data) {
    var entries = try load()
    guard entries[lease.id] == lease.references,
          references.isSubset(of: Set(lease.references)) else { throw ProjectSourceFiles.Failure.invalidFile }
    entries[lease.id] = lease.references.filter { !references.contains($0) }
    return (Self.key, try JSONEncoder().encode(entries))
  }

  func finish(_ lease: PDFSourceCopyLease) async throws {
    let entries = try load()
    guard let references = entries[lease.id] else { return }
    guard Set(references).isSubset(of: Set(lease.references)) else { throw ProjectSourceFiles.Failure.invalidFile }
    let files = ProjectSourceFiles(directory: directory)
    guard await files.removePendingCopies(references + references.map { ".stage-" + $0 }) else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
    // Other imports can commit while file I/O is awaited; merge into the fresh
    // ledger instead of overwriting their reservations with the old snapshot.
    var current = try load()
    guard current[lease.id] == references else { throw ProjectSourceFiles.Failure.invalidFile }
    current.removeValue(forKey: lease.id)
    try store.write(Self.key, data: JSONEncoder().encode(current))
    try? FileManager.default.removeItem(at: lease.lockURL)
  }

  func recover() async throws {
    for (id, references) in try load().sorted(by: { $0.key < $1.key }) {
      try Task.checkCancellation()
      // A live import owns this lock across all awaits, including its commit.
      guard let lease = try acquire(id: id, references: references) else { continue }
      try await finish(lease)
    }
  }

  private func load() throws -> [String: [String]] {
    let data: Data
    switch store.readOutcome(Self.key) {
    case .missing: return [:]
    case .data(let value): data = value
    case .failed: throw ProjectSourceFiles.Failure.invalidFile
    }
    guard data.count <= 4 * 1024 * 1024,
          let entries = try? JSONDecoder().decode([String: [String]].self, from: data),
          entries.count <= 256 else { throw ProjectSourceFiles.Failure.invalidFile }
    for (id, names) in entries {
      guard UUID(uuidString: id)?.uuidString == id, names.count <= 100,
            Set(names).count == names.count else { throw ProjectSourceFiles.Failure.invalidFile }
      let prefix = "pdfcopy-" + id + "-"
      for name in names {
        guard name.hasPrefix(prefix), name.hasSuffix(".pdf"),
              let index = Int(name.dropFirst(prefix.count).dropLast(4)),
              (1...100).contains(index), name == prefix + String(index) + ".pdf" else {
          throw ProjectSourceFiles.Failure.invalidFile
        }
      }
    }
    return entries
  }

  private func acquire(id: String, references: [String]) throws -> PDFSourceCopyLease? {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let root = directory.resolvingSymlinksInPath().standardizedFileURL
    let lockURL = root.appendingPathComponent(".pdfcopy-" + id + ".lock")
    let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw ProjectSourceFiles.Failure.invalidFile }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let code = errno
      close(descriptor)
      if code == EWOULDBLOCK || code == EAGAIN { return nil }
      throw ProjectSourceFiles.Failure.invalidFile
    }
    return PDFSourceCopyLease(id: id, references: references, lockURL: lockURL, descriptor: descriptor)
  }
}
