import Foundation

/// The share sheet may hold a file after the sheet closes. Exports of a saved
/// artifact are therefore copied beside it, and only those copies are removed.
enum ArtifactExportFile {
  static func copy(_ source: URL, preferredName: String, suffix: String,
                   directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
    let cleaned = preferredName
      .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let name = cleaned.isEmpty ? "資料" : String(cleaned.prefix(80))
    let safeSuffix = suffix.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    let destination = directory.appendingPathComponent(name + "-" + UUID().uuidString + "." + safeSuffix)
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
  }

  static func removeTemporary(_ items: [Any]) {
    for case let url as URL in items where url.isFileURL {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
