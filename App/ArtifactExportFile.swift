import Foundation

enum ArtifactExportFile {
  // A share sheet owns a disposable copy, never the stored artifact.
  static func copy(_ source: URL, preferredName: String, suffix: String,
                   directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
    let cleaned = preferredName
      .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let name = cleaned.isEmpty ? "資料" : String(cleaned.prefix(80))
    let safeSuffix = suffix.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    guard !safeSuffix.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
    let destination = directory.appendingPathComponent(name + "-" + UUID().uuidString + "." + safeSuffix)
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
  }

  static func removeTemporary(_ items: [Any]) {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
    for case let url as URL in items where url.isFileURL {
      guard url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == directory,
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true, values.isSymbolicLink != true else { continue }
      try? FileManager.default.removeItem(at: url)
    }
  }
}
