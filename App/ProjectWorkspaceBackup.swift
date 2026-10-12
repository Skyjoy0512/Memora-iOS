import Foundation

enum ProjectWorkspaceBackup {
  static let folderName = "workspace"

  static func export(_ sources: [ProjectSource], into package: URL) throws {
    let names = Set(sources.flatMap(\.fileReferences))
    guard !names.isEmpty else { return }
    let folder = package.appendingPathComponent(folderName, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in names {
      guard let source = ProjectSourceFiles.resolve(name), regular(source) else {
        throw BackupPackage.BackupError.missingSource([name])
      }
      try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
    }
  }

  static func validate(_ sources: [ProjectSource], in package: URL) throws {
    var total = 0
    for name in Set(sources.flatMap(\.fileReferences)) {
      guard ProjectSourceFiles.resolve(name) != nil else { throw BackupPackage.BackupError.unsafeReference(name) }
      let file = package.appendingPathComponent(folderName).appendingPathComponent(name)
      guard regular(file), let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            bytes <= ProjectSourceFiles.maximumFileBytes else { throw BackupPackage.BackupError.missingMedia([name]) }
      total += bytes
      guard total <= ProjectSourceFiles.maximumStorageBytes else { throw ProjectSourceFiles.Failure.capacity }
    }
  }

  static func install(_ sources: [ProjectSource], from package: URL) throws -> [String] {
    try validate(sources, in: package)
    let names = Set(sources.flatMap(\.fileReferences)).sorted()
    try FileManager.default.createDirectory(at: ProjectSourceFiles.directory, withIntermediateDirectories: true)
    var installed: [String] = []
    do {
      for name in names {
        guard let target = ProjectSourceFiles.resolve(name) else { throw BackupPackage.BackupError.unsafeReference(name) }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw BackupPackage.BackupError.mediaConflict(name) }
        try FileManager.default.copyItem(at: package.appendingPathComponent(folderName).appendingPathComponent(name), to: target)
        installed.append(name)
      }
      return installed
    } catch {
      remove(installed)
      throw error
    }
  }

  static func remove(_ installed: [String]) {
    for name in installed {
      if let file = ProjectSourceFiles.resolve(name) { try? FileManager.default.removeItem(at: file) }
    }
  }

  private static func regular(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
    return values.isRegularFile == true && values.isSymbolicLink != true
  }
}
