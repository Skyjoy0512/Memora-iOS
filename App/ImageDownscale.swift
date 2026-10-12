import Foundation
import UIKit
import ImageIO

/// Shrinks an image before storing it alongside a record or person.
enum ImageDownscale {
  static func jpeg(_ data: Data, maxSide: CGFloat = 320, quality: CGFloat = 0.8) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

    let resized = UIGraphicsImageRenderer(size: size).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return resized.jpegData(compressionQuality: quality)
  }

  /// Decodes a file at (roughly) the size it will be drawn, without ever holding
  /// the full image in memory. This is what lists use, so scrolling does not
  /// decode a full-size photo again for each row.
  static func downsampled(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

    return thumbnail(from: source, maxPixelSize: maxPixelSize)
  }

  static func downsampled(data: Data, maxPixelSize: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData,
      [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    return thumbnail(from: source, maxPixelSize: maxPixelSize)
  }

  private static func thumbnail(from source: CGImageSource, maxPixelSize: CGFloat) -> UIImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }
}
