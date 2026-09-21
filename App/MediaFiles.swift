import AVFoundation
import Foundation
import UIKit

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

  /// Resolves a stored reference back to a file. A relative name is a reference
  /// by construction; a legacy absolute path is only honoured when it still
  /// points at a file the app manages.
  static func resolve(_ stored: String) -> URL? {
    let managed = directory.standardizedFileURL

    if stored.hasPrefix("/") {
      let candidate = URL(fileURLWithPath: stored).standardizedFileURL
      guard candidate.path.hasPrefix(managed.path),
            FileManager.default.fileExists(atPath: candidate.path) else {
        return nil
      }
      return candidate
    }

    let candidate = managed.appendingPathComponent(stored).standardizedFileURL
    return candidate.path.hasPrefix(managed.path) ? candidate : nil
  }

  /// The folder photos are stored in.
  static var photosDirectory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Photos", isDirectory: true)
  }

  /// The small copy kept beside a stored photo. Derived from the stored name,
  /// so a record keeps one name and photos saved before thumbnails existed fall
  /// back to the full-size file.
  static func thumbnailName(for name: String) -> String {
    "\(name).thumb.jpg"
  }

  /// Writes a photo and returns the file name to store on the record. When
  /// `thumbnailMaxSide` is given, a small copy is written beside it so lists can
  /// draw a tile without decoding the full-size file.
  static func writePhoto(_ data: Data, thumbnailMaxSide: CGFloat? = nil) -> String? {
    let name = "\(UUID().uuidString).jpg"
    let url = photosDirectory.appendingPathComponent(name)
    do {
      try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      if let thumbnailMaxSide, let small = ImageDownscale.jpeg(data, maxSide: thumbnailMaxSide) {
        try? small.write(
          to: photosDirectory.appendingPathComponent(thumbnailName(for: name)),
          options: .atomic
        )
      }
      return name
    } catch {
      return nil
    }
  }

  /// The photo files that back the given names, including their thumbnails.
  static func photoFiles(for names: [String]) -> [String] {
    names.flatMap { [$0, thumbnailName(for: $0)] }
  }

  /// Resolves a stored photo file name, refusing anything outside the folder.
  static func photoURL(_ name: String) -> URL? {
    let root = photosDirectory.standardizedFileURL
    let url = root.appendingPathComponent(name).standardizedFileURL
    return url.path.hasPrefix(root.path) ? url : nil
  }

  static func photoData(_ name: String) -> Data? {
    guard let url = photoURL(name) else { return nil }
    return try? Data(contentsOf: url)
  }

  /// The small copy for lists, falling back to the full-size file for photos
  /// saved before thumbnails existed.
  static func photoThumbnailData(_ name: String) -> Data? {
    guard let url = photoURL(thumbnailName(for: name)),
          let data = try? Data(contentsOf: url) else {
      return photoData(name)
    }
    return data
  }

  @discardableResult
  static func deletePhoto(_ name: String) -> Bool {
    var removedEverything = true
    for candidate in [name, thumbnailName(for: name)] {
      guard let url = photoURL(candidate),
            FileManager.default.fileExists(atPath: url.path) else { continue }
      do {
        try FileManager.default.removeItem(at: url)
      } catch {
        removedEverything = false
      }
    }
    return removedEverything
  }

  /// The content type for a media file, taken from its extension so uploads
  /// describe what they actually contain.
  static func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "m4a", "mp4": "audio/mp4"
    case "mp3": "audio/mpeg"
    case "wav": "audio/wav"
    case "aif", "aiff": "audio/aiff"
    case "caf": "audio/x-caf"
    case "flac": "audio/flac"
    case "ogg": "audio/ogg"
    default: "application/octet-stream"
    }
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
