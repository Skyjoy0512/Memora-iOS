import UIKit

/// Decoded photos, keyed by file name, so a list that re-renders while scrolling
/// does not decode the same image again for every pass. File names are unique
/// per photo, so an entry can never be stale; the count limit evicts the rest.
@MainActor
enum MediaImageCache {
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 80
    return cache
  }()

  /// The small copy a list draws.
  static func thumbnail(named name: String) -> UIImage? {
    decoded(key: name) { MediaFiles.photoThumbnailData(name) }
  }

  /// The full-size photo, for the one being looked at.
  static func photo(named name: String) -> UIImage? {
    decoded(key: "full.\(name)") { MediaFiles.photoData(name) }
  }

  private static func decoded(key: String, data: () -> Data?) -> UIImage? {
    if let cached = cache.object(forKey: key as NSString) {
      return cached
    }
    guard let bytes = data(), let image = UIImage(data: bytes) else { return nil }
    cache.setObject(image, forKey: key as NSString)
    return image
  }
}
