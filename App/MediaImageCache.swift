import UIKit

/// Decoded photos for lists, decoded at the size they are drawn and off the main
/// thread, keyed by file name and size. File names are unique per photo, so an
/// entry can never be stale; the count limit evicts the rest.
@MainActor
enum MediaImageCache {
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 80
    return cache
  }()

  /// The photo for a list, decoded at `maxPixelSize`.
  static func image(named name: String, maxPixelSize: CGFloat) async -> UIImage? {
    let key = "\(name)@\(Int(maxPixelSize))"
    if let cached = cache.object(forKey: key as NSString) {
      return cached
    }
    guard let url = thumbnailURL(for: name) else { return nil }

    let image = await Task.detached(priority: .userInitiated) {
      ImageDownscale.downsampled(at: url, maxPixelSize: maxPixelSize)
    }.value

    guard let image else { return nil }
    cache.setObject(image, forKey: key as NSString)
    return image
  }

  /// The full-size photo, for the one being looked at.
  static func photo(named name: String, maxPixelSize: CGFloat = 2_000) async -> UIImage? {
    let key = "full.\(name)@\(Int(maxPixelSize))"
    if let cached = cache.object(forKey: key as NSString) {
      return cached
    }
    guard let url = MediaFiles.photoURL(name) else { return nil }

    let image = await Task.detached(priority: .userInitiated) {
      ImageDownscale.downsampled(at: url, maxPixelSize: maxPixelSize)
    }.value

    guard let image else { return nil }
    cache.setObject(image, forKey: key as NSString)
    return image
  }

  /// The small copy when it exists; otherwise the original, which is all there
  /// is for photos saved before thumbnails did.
  private static func thumbnailURL(for name: String) -> URL? {
    MediaFiles.photoURL(MediaFiles.thumbnailName(for: name)) ?? MediaFiles.photoURL(name)
  }
}
