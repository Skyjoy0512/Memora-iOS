import Darwin
import Foundation

actor SourceMediaStaging {
  static let shared = SourceMediaStaging()
  static let maximumStageBytes: Int64 = 128 * 1_024 * 1_024
  static let maximumTotalBytes: Int64 = 256 * 1_024 * 1_024
  static let minimumAvailableBytes: Int64 = 256 * 1_024 * 1_024
  static let staleAge: TimeInterval = 60 * 60
  private let directory: URL
  private let availableCapacity: @Sendable (URL) throws -> Int64

  init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraSourceMedia", isDirectory: true),
       availableCapacity: @escaping @Sendable (URL) throws -> Int64 = SourceMediaStaging.availableBytes) {
    self.directory = directory
    self.availableCapacity = availableCapacity
  }

  func acquire() throws -> SourceMediaStageLease {
    try Task.checkCancellation()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let rootValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw SourceMediaFailure.invalidTemporaryFile }
    try cleanupStale()
    let stages = try stageDirectories()
    guard stages.count < 32, try Self.size(of: directory) <= Self.maximumTotalBytes - Self.maximumStageBytes else {
      throw SourceMediaFailure.stagingLimit
    }
    guard try availableCapacity(directory) >= Self.minimumAvailableBytes else { throw SourceMediaFailure.capacity }
    let stage = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let descriptor = open(stage.appendingPathComponent(".lease").path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { try? FileManager.default.removeItem(at: stage); throw SourceMediaFailure.invalidTemporaryFile }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      try? FileManager.default.removeItem(at: stage)
      throw SourceMediaFailure.invalidTemporaryFile
    }
    return SourceMediaStageLease(directory: stage, descriptor: descriptor)
  }

  func cleanupStale(now: Date = .now) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for stage in try stageDirectories() {
      let values = try stage.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
      let lease = stage.appendingPathComponent(".lease")
      if !FileManager.default.fileExists(atPath: lease.path) {
        // Creation and lease acquisition are separate filesystem operations.
        // A new directory without a lease may still belong to a starting task.
        if let created = values.creationDate ?? values.contentModificationDate,
           now.timeIntervalSince(created) >= Self.staleAge { try? FileManager.default.removeItem(at: stage) }
        continue
      }
      let descriptor = open(lease.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { continue }
      defer { close(descriptor) }
      guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
      defer { flock(descriptor, LOCK_UN) }
      try? FileManager.default.removeItem(at: stage)
    }
  }

  static func size(of root: URL) throws -> Int64 {
    let manager = FileManager.default
    let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw SourceMediaFailure.invalidTemporaryFile }
    var bytes: Int64 = 0
    var folders = [root]
    while let folder = folders.popLast() {
      let files: [URL]
      do { files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) }
      catch where isMissing(error) { continue }
      for file in files {
        let values: URLResourceValues
        do { values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) }
        catch where isMissing(error) { continue }
        guard values.isSymbolicLink != true else { throw SourceMediaFailure.invalidTemporaryFile }
        if values.isDirectory == true { folders.append(file) }
        else if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        else { throw SourceMediaFailure.invalidTemporaryFile }
        if bytes > maximumTotalBytes { return bytes }
      }
    }
    return bytes
  }

  private static func isMissing(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) ||
      error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
  }

  private func stageDirectories() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      .filter { url in
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return UUID(uuidString: url.lastPathComponent) != nil && values.isDirectory == true && values.isSymbolicLink != true
      }
  }

  static func availableBytes(_ directory: URL) throws -> Int64 {
    let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
    guard let bytes = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) else {
      throw SourceMediaFailure.capacity
    }
    return bytes
  }
}
