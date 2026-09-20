import AVFoundation
import Foundation

/// Owns the app's media files. Everything lives inside the app's container, and
/// only files that belong there are ever removed.
enum MediaFiles {
  /// The folder recordings and imported audio are copied into.
  static var directory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Recordings", isDirectory: true)
  }

  /// The length of a media file, or nil when it cannot be read.
  static func duration(of url: URL) async -> TimeInterval? {
    let asset = AVURLAsset(url: url)
    guard let duration = try? await asset.load(.duration) else { return nil }
    let seconds = CMTimeGetSeconds(duration)
    return seconds.isFinite && seconds > 0 ? seconds : nil
  }

  /// The managed path for a file, relative to the media folder, so records do
  /// not depend on the container's absolute path. Nil when the file is not ours.
  static func reference(for url: URL) -> String? {
    let managed = directory.standardizedFileURL.path
    let target = url.standardizedFileURL.path
    guard target.hasPrefix(managed + "/") else { return nil }
    return String(target.dropFirst(managed.count + 1))
  }

  /// Resolves a stored reference back to a file. Legacy absolute paths are only
  /// honoured when they point inside the managed folder and the file is there.
  static func resolve(_ stored: String) -> URL? {
    let managed = directory.standardizedFileURL
    let candidate = stored.hasPrefix("/")
      ? URL(fileURLWithPath: stored).standardizedFileURL
      : managed.appendingPathComponent(stored).standardizedFileURL

    guard candidate.path.hasPrefix(managed.path),
          FileManager.default.fileExists(atPath: candidate.path) else {
      return nil
    }
    return candidate
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
