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

  /// A stored media name must be a plain file name: no path separators, no
  /// `.`/`..`, and nothing that could name the folder itself. Media never lives
  /// in subfolders, so anything else is refused.
  static func isPlainName(_ name: String) -> Bool {
    guard !name.isEmpty, name != ".", name != ".." else { return false }
    guard !name.contains("/"), !name.contains("\\") else { return false }
    guard !name.contains("\0") else { return false }
    return true
  }

  /// True when `url` is a file strictly inside `folder`, after resolving
  /// symlinks. A shared string prefix ("Recordings" vs "RecordingsOld") or the
  /// folder itself does not count, so nothing outside is ever written or erased.
  static func isInside(_ url: URL, folder: URL) -> Bool {
    let target = url.resolvingSymlinksInPath().standardizedFileURL
    let root = folder.resolvingSymlinksInPath().standardizedFileURL
    guard target.path != root.path else { return false }
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return target.path.hasPrefix(rootPrefix)
  }

  /// The managed path for a file, relative to the media folder, so records do
  /// not depend on the container's absolute path. Nil when the file is not ours,
  /// when it is the folder itself, or when it sits in a subfolder.
  static func reference(for url: URL) -> String? {
    guard isInside(url, folder: directory) else { return nil }
    let managed = directory.resolvingSymlinksInPath().standardizedFileURL.path
    let target = url.resolvingSymlinksInPath().standardizedFileURL.path
    let name = String(target.dropFirst(managed.count + 1))
    return isPlainName(name) ? name : nil
  }

  /// Resolves a stored reference back to a file. A relative name must be a plain
  /// file name; a legacy absolute path is only honoured when it still points at
  /// a file inside the app's folder.
  static func resolve(_ stored: String) -> URL? {
    if stored.hasPrefix("/") {
      let candidate = URL(fileURLWithPath: stored)
      guard isInside(candidate, folder: directory),
            FileManager.default.fileExists(atPath: candidate.path) else {
        return nil
      }
      return candidate
    }

    guard isPlainName(stored) else { return nil }
    let candidate = directory.appendingPathComponent(stored)
    return isInside(candidate, folder: directory) ? candidate : nil
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

  /// Resolves a stored photo file name, refusing anything that is not a plain
  /// name inside the photo folder.
  static func photoURL(_ name: String) -> URL? {
    guard isPlainName(name) else { return nil }
    let url = photosDirectory.appendingPathComponent(name)
    return isInside(url, folder: photosDirectory) ? url : nil
  }

  /// The originals a record needs, as opposed to thumbnails, which can always be
  /// built again from the original.
  static func requiredPhotoFiles(for name: String) -> [String] {
    [name]
  }

  /// The small copies that can be regenerated, so a backup can carry them when
  /// they exist without failing over one that is missing.
  static func regenerablePhotoFiles(for name: String) -> [String] {
    [thumbnailName(for: name)]
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

    // Only a regular file strictly inside the managed folder is ours to remove.
    // The folder itself and anything reached through a symlink are left alone.
    guard isInside(url, folder: directory) else { return true }
    let target = url.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      return true
    }

    do {
      try FileManager.default.removeItem(at: target)
      return true
    } catch {
      return false
    }
  }
}
