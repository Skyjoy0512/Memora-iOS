import CryptoKit
import Foundation

struct PDFSourcePartitionSnapshot {
  var original: URL
  var url: URL
  var fingerprint: String
  private var attributes: Attributes

  init(_ original: URL, in directory: URL) throws {
    let before = try Self.attributes(original)
    let target = directory.appendingPathComponent("original.pdf")
    guard FileManager.default.createFile(atPath: target.path, contents: nil,
      attributes: [.posixPermissions: 0o600]) else { throw PDFSourcePartitionFailure.writeFailed }
    do {
      let input = try FileHandle(forReadingFrom: original)
      defer { try? input.close() }
      let output = try FileHandle(forWritingTo: target)
      defer { try? output.close() }
      var hash = SHA256(), bytes = 0
      while let block = try input.read(upToCount: 1024 * 1024), !block.isEmpty {
        try Task.checkCancellation()
        bytes += block.count
        guard bytes <= PDFSourcePartition.maximumInputBytes else { throw PDFSourcePartitionFailure.inputTooLarge }
        hash.update(data: block)
        try output.write(contentsOf: block)
      }
      try Task.checkCancellation()
      try output.synchronize()
      try output.close()
      let fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
      guard bytes == before.bytes, try Self.attributes(original) == before,
            try Self.digest(original) == fingerprint else { throw PDFSourcePartitionFailure.originalChanged }
      self.original = original
      url = target
      self.fingerprint = fingerprint
      attributes = before
    } catch {
      try? FileManager.default.removeItem(at: target)
      throw error
    }
  }

  func verifyOriginal() throws {
    guard try Self.attributes(original) == attributes, try Self.digest(original) == fingerprint else {
      throw PDFSourcePartitionFailure.originalChanged
    }
  }

  private static func attributes(_ url: URL) throws -> Attributes {
    guard url.isFileURL else { throw PDFSourcePartitionFailure.invalidFile }
    let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey,
      .fileSizeKey, .contentModificationDateKey])
    guard properties.isRegularFile == true, properties.isSymbolicLink != true, let bytes = properties.fileSize else {
      throw PDFSourcePartitionFailure.invalidFile
    }
    guard bytes > 0 else { throw PDFSourcePartitionFailure.invalidFile }
    guard bytes <= PDFSourcePartition.maximumInputBytes else { throw PDFSourcePartitionFailure.inputTooLarge }
    return .init(bytes: bytes, modified: properties.contentModificationDate)
  }

  private static func digest(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hash = SHA256(), bytes = 0
    while let block = try file.read(upToCount: 1024 * 1024), !block.isEmpty {
      try Task.checkCancellation()
      bytes += block.count
      guard bytes <= PDFSourcePartition.maximumInputBytes else { throw PDFSourcePartitionFailure.inputTooLarge }
      hash.update(data: block)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private struct Attributes: Equatable {
    var bytes: Int
    var modified: Date?
  }
}
