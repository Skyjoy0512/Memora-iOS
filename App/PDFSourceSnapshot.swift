import CryptoKit
import Foundation

/// PDFKit can read a document lazily. An immutable temporary snapshot prevents
/// a file changed during OCR from contaminating another original's checkpoints.
struct PDFSourceSnapshot {
  var original: URL
  var url: URL
  var fingerprint: String
  private var originalAttributes: Attributes

  init(_ original: URL) throws {
    let before = try Self.attributes(original)
    let directory = Self.directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // PDFSourceExtraction serializes reads, so these belong to interrupted runs.
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where file.lastPathComponent.hasPrefix("page-input-") && file.pathExtension == "pdf" {
      try? FileManager.default.removeItem(at: file)
    }
    let snapshot = directory.appendingPathComponent("page-input-\(UUID().uuidString).pdf")
    do {
      try FileManager.default.copyItem(at: original, to: snapshot)
      _ = try Self.attributes(snapshot)
      let hash = try Self.digest(snapshot)
      guard try Self.attributes(original) == before, try Self.digest(original) == hash else {
        throw ProjectSourceFiles.Failure.invalidFile
      }
      self.original = original
      url = snapshot
      fingerprint = hash
      originalAttributes = before
    } catch {
      try? FileManager.default.removeItem(at: snapshot)
      throw error
    }
  }

  func verifyOriginal() throws {
    guard try Self.attributes(original) == originalAttributes, try Self.digest(original) == fingerprint else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
  }

  func remove() { try? FileManager.default.removeItem(at: url) }

  private static var directory: URL {
    #if MEMORA_HOST_CHECKS
    return ProjectSourceFiles.directory.appendingPathComponent("PDFSnapshots", isDirectory: true)
    #else
    return FileManager.default.temporaryDirectory.appendingPathComponent("MemoraPDFSnapshots", isDirectory: true)
    #endif
  }

  private static func attributes(_ url: URL) throws -> Attributes {
    guard url.isFileURL else { throw ProjectSourceFiles.Failure.invalidFile }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
    guard size <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    return .init(modified: values.contentModificationDate, bytes: size)
  }

  private static func digest(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256(), count = 0
    while let bytes = try file.read(upToCount: 64 * 1024), !bytes.isEmpty {
      try Task.checkCancellation()
      count += bytes.count
      guard count <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
      hash.update(data: bytes)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private struct Attributes: Equatable {
    var modified: Date?
    var bytes: Int
  }
}
