import Darwin
import Foundation

/// Only named partition UUID directories belong to this allocator. Other files
/// in a caller-supplied parent are neither inspected recursively nor removed.
enum PDFSourcePartitionStaging {
  static let maximumDirectories = 8
  static let maximumTotalBytes: Int64 = 1_024 * 1_024 * 1_024
  static let minimumReserveBytes: Int64 = 64 * 1_024 * 1_024
  static let preleaseGrace: TimeInterval = 60 * 60

  static func acquire(in base: URL, inputBytes: Int,
                      availableCapacity: (URL) throws -> Int64 = availableBytes) throws -> PDFSourcePartitionLease {
    try Task.checkCancellation()
    guard inputBytes > 0, inputBytes <= PDFSourcePartition.maximumInputBytes else { throw PDFSourcePartitionFailure.invalidFile }
    guard base.isFileURL else { throw PDFSourcePartitionFailure.invalidFile }
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let properties = try base.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard properties.isDirectory == true, properties.isSymbolicLink != true else { throw PDFSourcePartitionFailure.invalidFile }
    let root = base.resolvingSymlinksInPath().standardizedFileURL
    let allocation = open(root.appendingPathComponent(".partition-allocation").path,
      O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard allocation >= 0 else { throw PDFSourcePartitionFailure.writeFailed }
    defer { close(allocation) }
    guard flock(allocation, LOCK_EX | LOCK_NB) == 0 else { throw PDFSourcePartitionFailure.stagingBusy }
    defer { flock(allocation, LOCK_UN) }
    try cleanupInactive(in: root)
    let stages = try stageDirectories(in: root)
    let reserved = Int64(inputBytes) + Int64(PDFSourcePartition.maximumOutputBytes) + 4_096
    guard stages.count < maximumDirectories, reserved <= maximumTotalBytes else { throw PDFSourcePartitionFailure.stagingLimit }
    var occupied: Int64 = 0
    for stage in stages {
      try Task.checkCancellation()
      // A live writer may still grow. Reserve its promised input/output budget,
      // rather than admitting another job based only on today's partial file.
      let actual = try bytes(in: stage)
      let promised = try reservation(in: stage) ?? Int64(PDFSourcePartition.maximumInputBytes + PDFSourcePartition.maximumOutputBytes + 4_096)
      occupied += max(actual, promised)
      guard occupied <= maximumTotalBytes - reserved else { throw PDFSourcePartitionFailure.stagingLimit }
    }
    guard try availableCapacity(root) >= Int64(inputBytes) + minimumReserveBytes else { throw PDFSourcePartitionFailure.insufficientCapacity }
    let directory = root.appendingPathComponent("partition-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    let descriptor = open(directory.appendingPathComponent(".lease").path,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      try? FileManager.default.removeItem(at: directory)
      throw PDFSourcePartitionFailure.writeFailed
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      try? FileManager.default.removeItem(at: directory)
      throw PDFSourcePartitionFailure.stagingBusy
    }
    let lease = PDFSourcePartitionLease(directory: directory, descriptor: descriptor)
    do { try Data(String(reserved).utf8).write(to: directory.appendingPathComponent(".reservation"), options: .atomic) }
    catch { lease.remove(); throw error }
    return lease
  }

  static func ensureWriteCapacity(in directory: URL) throws {
    try Task.checkCancellation()
    guard try availableBytes(directory) >= Int64(PDFSourcePartition.maximumPartBytes) + minimumReserveBytes else {
      throw PDFSourcePartitionFailure.insufficientCapacity
    }
  }

  static func availableBytes(_ directory: URL) throws -> Int64 {
    let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
    guard let bytes = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) else {
      throw PDFSourcePartitionFailure.insufficientCapacity
    }
    return bytes
  }

  private static func cleanupInactive(in root: URL, now: Date = .now) throws {
    for directory in try stageDirectories(in: root) {
      try Task.checkCancellation()
      let file = directory.appendingPathComponent(".lease")
      let descriptor = open(file.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
      if descriptor < 0 {
        // The lease file may not exist yet during directory creation. Only an
        // old prelease folder is safe to discard; unreadable leases are retained.
        guard errno == ENOENT else { continue }
        let properties = try directory.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        if let created = properties.creationDate ?? properties.contentModificationDate,
           now.timeIntervalSince(created) >= preleaseGrace { try? FileManager.default.removeItem(at: directory) }
        continue
      }
      defer { close(descriptor) }
      guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
      defer { flock(descriptor, LOCK_UN) }
      try? FileManager.default.removeItem(at: directory)
    }
  }

  private static func stageDirectories(in root: URL) throws -> [URL] {
    var result: [URL] = []
    for url in try childURLs(in: root, limit: 4_096) {
      let name = url.lastPathComponent
      guard name.hasPrefix("partition-"), UUID(uuidString: String(name.dropFirst("partition-".count))) != nil else { continue }
      let properties = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard properties.isDirectory == true, properties.isSymbolicLink != true else { continue }
      result.append(url)
      // Admission can reject huge sets without reading their contents. Recovery
      // still examines leases so interrupted jobs do not accumulate indefinitely.
    }
    return result
  }

  private static func bytes(in directory: URL) throws -> Int64 {
    let files = try childURLs(in: directory, limit: PDFSourcePartition.maximumParts + 8)
    var total: Int64 = 0
    for file in files {
      let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard properties.isRegularFile == true, properties.isSymbolicLink != true,
            let bytes = properties.fileSize, bytes >= 0 else { throw PDFSourcePartitionFailure.stagingLimit }
      guard Int64(bytes) <= maximumTotalBytes - total else { return maximumTotalBytes + 1 }
      total += Int64(bytes)
    }
    return total
  }

  private static func reservation(in directory: URL) throws -> Int64? {
    let file = directory.appendingPathComponent(".reservation")
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard properties.isRegularFile == true, properties.isSymbolicLink != true,
          let size = properties.fileSize, (1...64).contains(size) else { throw PDFSourcePartitionFailure.stagingLimit }
    let reader = try FileHandle(forReadingFrom: file)
    defer { try? reader.close() }
    let data = try reader.read(upToCount: 65) ?? Data()
    guard data.count <= 64, let text = String(data: data, encoding: .utf8),
          let bytes = Int64(text), bytes >= 0, bytes <= maximumTotalBytes else { throw PDFSourcePartitionFailure.stagingLimit }
    return bytes
  }

  private static func childURLs(in directory: URL, limit: Int) throws -> [URL] {
    var failure: Error?
    guard let enumeration = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
      options: [.skipsSubdirectoryDescendants], errorHandler: { _, error in failure = error; return false }) else {
      throw PDFSourcePartitionFailure.stagingLimit
    }
    var result: [URL] = []
    while let url = enumeration.nextObject() as? URL {
      try Task.checkCancellation()
      guard result.count < limit else { throw PDFSourcePartitionFailure.stagingLimit }
      result.append(url)
    }
    if let failure { throw failure }
    return result
  }
}
