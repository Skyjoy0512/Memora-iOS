import Foundation

/// Owns the app's media files. Everything lives inside the app's container, and
/// only files that belong there are ever removed.
enum MediaFiles {
  /// The folder recordings and imported audio are copied into.
  static var directory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Recordings", isDirectory: true)
  }

  /// Deletes a file the app manages. Returns false when a file that should have
  /// been removed could not be, so the caller can tell the person.
  @discardableResult
  static func delete(_ url: URL?) -> Bool {
    guard let url, url.isFileURL else { return true }

    let managed = directory.standardizedFileURL.path
    let target = url.standardizedFileURL
    // Anything outside the managed folder is not ours to delete.
    guard target.path.hasPrefix(managed) else { return true }

    guard FileManager.default.fileExists(atPath: target.path) else { return true }

    do {
      try FileManager.default.removeItem(at: target)
      return true
    } catch {
      return false
    }
  }
}
