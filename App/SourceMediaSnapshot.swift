import CryptoKit
import Foundation

/// Checkpoints describe this bounded, immutable copy, even if an external
/// provider replaces the original while speech recognition is suspended.
struct SourceMediaSnapshot {
  var url: URL
  var fingerprint: String
  private var original: URL
  private var originalAttributes: Attributes

  init(_ original: URL, directory: URL) throws {
    let before = try Self.attributes(original)
    let url = directory.appendingPathComponent("input").appendingPathExtension(original.pathExtension)
    let digest = try Self.copy(original, to: url)
    guard try Self.attributes(original) == before, try Self.digest(original) == digest else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
    self.url = url
    fingerprint = digest
    self.original = original
    originalAttributes = before
  }

  func verifyOriginal() throws {
    guard try Self.attributes(original) == originalAttributes, try Self.digest(original) == fingerprint else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
  }

  private static func copy(_ original: URL, to copy: URL) throws -> String {
    guard FileManager.default.createFile(atPath: copy.path, contents: nil,
      attributes: [.posixPermissions: 0o600]) else { throw ProjectSourceFiles.Failure.invalidFile }
    let input = try FileHandle(forReadingFrom: original)
    defer { try? input.close() }
    let output = try FileHandle(forWritingTo: copy)
    defer { try? output.close() }
    var hash = SHA256(), count = 0
    while let bytes = try input.read(upToCount: 64 * 1024), !bytes.isEmpty {
      try Task.checkCancellation()
      count += bytes.count
      guard count <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
      try output.write(contentsOf: bytes)
      hash.update(data: bytes)
    }
    guard count > 0 else { throw ProjectSourceFiles.Failure.invalidFile }
    try output.synchronize()
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func digest(_ url: URL) throws -> String {
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    var hash = SHA256(), count = 0
    while let bytes = try input.read(upToCount: 64 * 1024), !bytes.isEmpty {
      try Task.checkCancellation()
      count += bytes.count
      guard count <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
      hash.update(data: bytes)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func attributes(_ url: URL) throws -> Attributes {
    guard url.isFileURL else { throw ProjectSourceFiles.Failure.invalidFile }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let bytes = values.fileSize, bytes > 0 else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
    guard bytes <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    return Attributes(bytes: bytes, modified: values.contentModificationDate)
  }

  private struct Attributes: Equatable {
    var bytes: Int
    var modified: Date?
  }
}
