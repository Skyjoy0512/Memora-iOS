import Foundation

/// The share sheet may hold a file after the sheet closes. Exports of a saved
/// artifact are therefore copied beside it, and only those copies are removed.
enum ArtifactExportFile {
  static func copy(_ source: URL, preferredName: String, suffix: String,
                   directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
    let name = preferredName.isEmpty ? "資料" : preferredName
    let destination = directory.appendingPathComponent(name + "-" + UUID().uuidString + "." + suffix)
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
  }

  static func removeTemporary(_ items: [Any]) {
    for case let url as URL in items where url.isFileURL {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
