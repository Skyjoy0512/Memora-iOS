import Foundation
import CryptoKit

actor ProjectSourceFiles {
  static let shared = ProjectSourceFiles()
  private var root: URL

  init(directory: URL = ProjectSourceFiles.directory) { root = directory }

  static let maximumFileBytes = 50 * 1024 * 1024
  static let maximumStorageBytes = 500 * 1024 * 1024
  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Memora/WorkspaceFiles", isDirectory: true)
  }

  struct Receipt: Sendable {
    var reference: String
    var fingerprint: String
  }

  enum Failure: LocalizedError {
    case tooLarge, capacity, invalidFile
    var errorDescription: String? {
      switch self {
      case .tooLarge: "ファイルは50MB以下にしてください。"
      case .capacity: "ソース保存容量の上限（500MB）に達しました。"
      case .invalidFile: "このファイルを読み込めませんでした。"
      }
    }
  }

  static func resolve(_ name: String, in folder: URL? = nil) -> URL? {
    let directory = folder ?? Self.directory
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
          !name.contains("\\"), !name.contains("\0") else { return nil }
    let url = directory.appendingPathComponent(name)
    let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else { return nil }
    return url
  }

  func copy(_ source: URL) throws -> Receipt {
    let accessed = source.startAccessingSecurityScopedResource()
    defer { if accessed { source.stopAccessingSecurityScopedResource() } }
    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalidFile }
    guard (values.fileSize ?? Int.max) <= Self.maximumFileBytes else { throw Failure.tooLarge }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let staging = root.appendingPathComponent(".stage-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: staging.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: staging) }
    let reader = try FileHandle(forReadingFrom: source)
    let writer = try FileHandle(forWritingTo: staging)
    defer { try? reader.close(); try? writer.close() }
    var digest = SHA256()
    var count = 0
    while let bytes = try reader.read(upToCount: 64 * 1024), !bytes.isEmpty {
      try Task.checkCancellation()
      count += bytes.count
      guard count <= Self.maximumFileBytes else { throw Failure.tooLarge }
      digest.update(data: bytes)
      try writer.write(contentsOf: bytes)
    }
    try writer.synchronize()
    try writer.close()
    let suffix = source.pathExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    let name = UUID().uuidString + (suffix.isEmpty ? "" : "." + String(suffix.prefix(12)))
    let total = try occupiedBytes()
    guard total <= Self.maximumStorageBytes else { throw Failure.capacity }
    try FileManager.default.moveItem(at: staging, to: root.appendingPathComponent(name))
    return Receipt(reference: name, fingerprint: digest.finalize().map { String(format: "%02x", $0) }.joined())
  }

  func write(_ data: Data, extension suffix: String) throws -> String {
    guard data.count <= Self.maximumFileBytes else { throw Failure.tooLarge }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    guard try occupiedBytes() + data.count <= Self.maximumStorageBytes else { throw Failure.capacity }
    let safeSuffix = suffix.filter { $0.isASCII && $0.isLetter }
    let name = UUID().uuidString + "." + safeSuffix
    guard let url = Self.resolve(name, in: root) else { throw Failure.invalidFile }
    try data.write(to: url, options: .atomic)
    return name
  }

  func remove(_ names: [String]) {
    for name in Set(names) {
      if let url = Self.resolve(name, in: root) { try? FileManager.default.removeItem(at: url) }
    }
  }

  private func occupiedBytes() throws -> Int {
    try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])
      .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }
}
