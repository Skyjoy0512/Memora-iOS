import Foundation

/// The sizes of what Memora keeps on disk, grouped so the storage screen can
/// show where the space went.
enum StorageUsage {
  struct Breakdown {
    var audio: Int64
    var photos: Int64
    var other: Int64
    var total: Int64 { audio + photos + other }
  }

  private static let audioExtensions: Set<String> = [
    "m4a", "mp3", "wav", "caf", "aiff", "aif", "aac", "flac", "ogg", "mp4", "mov", "m4v"
  ]
  private static let photoExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif"
  ]

  static func current() -> Breakdown {
    var audio: Int64 = 0
    var photos: Int64 = 0
    var other: Int64 = 0

    let folder = MediaFiles.directory
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    let enumerator = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    )
    while let url = enumerator?.nextObject() as? URL {
      let values = try? url.resourceValues(forKeys: Set(keys))
      guard values?.isRegularFile == true else { continue }
      let size = Int64(values?.fileSize ?? 0)
      let ext = url.pathExtension.lowercased()
      if audioExtensions.contains(ext) {
        audio += size
      } else if photoExtensions.contains(ext) || ext.contains("thumb") {
        photos += size
      } else {
        other += size
      }
    }
    return Breakdown(audio: audio, photos: photos, other: other)
  }

  static func size(of url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
  }

  static func text(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
