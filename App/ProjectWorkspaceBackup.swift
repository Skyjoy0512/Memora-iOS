import Foundation

enum ProjectWorkspaceBackup {
  static let folderName = "workspace"

  static func export(_ sources: [ProjectSource], into package: URL, additionalNames: [String] = []) throws {
    let names = Set(sources.flatMap(\.fileReferences) + additionalNames)
    guard !names.isEmpty else { return }
    let folder = package.appendingPathComponent(folderName, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in names {
      try Task.checkCancellation()
      guard let source = ProjectSourceFiles.resolve(name), regular(source) else {
        throw BackupPackage.BackupError.missingSource([name])
      }
      try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
    }
    try validate(sources, in: package, additionalNames: additionalNames)
  }

  static func validate(_ sources: [ProjectSource], in package: URL, additionalNames: [String] = []) throws {
    var total = 0
    for name in Set(sources.flatMap(\.fileReferences) + additionalNames) {
      try Task.checkCancellation()
      guard MediaFiles.isPlainName(name) else { throw BackupPackage.BackupError.unsafeReference(name) }
      guard let file = BackupPackageFile.resolve(name, folder: folderName, in: package),
            let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            bytes <= ProjectSourceFiles.maximumFileBytes else { throw BackupPackage.BackupError.missingMedia([name]) }
      total += bytes
      guard total <= ProjectSourceFiles.maximumStorageBytes else { throw ProjectSourceFiles.Failure.capacity }
    }
  }

  static func install(_ sources: [ProjectSource], from package: URL, additionalNames: [String] = []) throws -> [String] {
    try validate(sources, in: package, additionalNames: additionalNames)
    let names = Set(sources.flatMap(\.fileReferences) + additionalNames).sorted()
    try FileManager.default.createDirectory(at: ProjectSourceFiles.directory, withIntermediateDirectories: true)
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraWorkspaceRestore-\(UUID())")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    // Check the copies as well: a file provider may have changed its package since read().
    let stagedFolder = staging.appendingPathComponent(folderName)
    try FileManager.default.createDirectory(at: stagedFolder, withIntermediateDirectories: true)
    for name in names {
      try Task.checkCancellation()
      guard let source = BackupPackageFile.resolve(name, folder: folderName, in: package) else {
        throw BackupPackage.BackupError.missingMedia([name])
      }
      try FileManager.default.copyItem(at: source, to: stagedFolder.appendingPathComponent(name))
    }
    try validate(sources, in: staging, additionalNames: additionalNames)
    var installed: [String] = []
    do {
      for name in names {
        try Task.checkCancellation()
        guard let target = ProjectSourceFiles.resolve(name) else { throw BackupPackage.BackupError.unsafeReference(name) }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw BackupPackage.BackupError.mediaConflict(name) }
        try FileManager.default.moveItem(at: stagedFolder.appendingPathComponent(name), to: target)
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
