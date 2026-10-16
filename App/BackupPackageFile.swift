import Foundation

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
}
