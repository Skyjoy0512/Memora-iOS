import Foundation
import Darwin

enum BackupPackageFile {
  /// A plain filename alone does not prevent a containing folder from being a link.
  static func resolve(_ name: String, folder: String? = nil, in package: URL) -> URL? {
    guard MediaFiles.isPlainName(name) else { return nil }
    let root = package.resolvingSymlinksInPath().standardizedFileURL
    let directory = folder.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
    let file = directory.appendingPathComponent(name)
    guard file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.path + "/"),
          let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
    if folder != nil {
      guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true, values.isSymbolicLink != true else { return nil }
    }
    return file
  }

  /// Check the opened file, then read in bounded chunks even if it grows after stat.
  static func read(_ name: String, in package: URL, maximumBytes: Int) throws -> Data {
    try Task.checkCancellation()
    guard maximumBytes > 0, maximumBytes < Int.max,
          let file = resolve(name, in: package) else { throw BackupPackage.BackupError.unreadable }
    let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw BackupPackage.BackupError.unreadable }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          metadata.st_size >= 0 else { throw BackupPackage.BackupError.unreadable }
    guard metadata.st_size <= maximumBytes else { throw BackupPackage.BackupError.manifestTooLarge }
    var data = Data()
    while true {
      try Task.checkCancellation()
      let bytes = try handle.read(upToCount: min(64 * 1024, maximumBytes - data.count + 1)) ?? Data()
      guard !bytes.isEmpty else { break }
      guard bytes.count <= maximumBytes - data.count else { throw BackupPackage.BackupError.manifestTooLarge }
      data.append(bytes)
    }
    try Task.checkCancellation()
    return data
  }

}
