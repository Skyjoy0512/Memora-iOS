import Foundation

enum VoiceProfileFiles {
  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("VoiceSamples", isDirectory: true)
  }

  static func prepareDirectory() throws -> URL {
    var folder = directory
    try FileManager.default.createDirectory(
      at: folder,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete]
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    return folder
  }

  static func resolve(_ fileName: String) -> URL? {
    guard MediaFiles.isPlainName(fileName), fileName.hasPrefix("Memora-"),
          fileName.hasSuffix(".m4a") else { return nil }
    let url = directory.appendingPathComponent(fileName)
    return MediaFiles.isInside(url, folder: directory) ? url : nil
  }

  static func remove(_ fileName: String) throws {
    guard let url = resolve(fileName) else { throw CocoaError(.fileReadInvalidFileName) }
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  static func removeUnused(keeping fileName: String?) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
      guard url.lastPathComponent != fileName,
            resolve(url.lastPathComponent) != nil,
            try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
      try remove(url.lastPathComponent)
    }
  }
}
