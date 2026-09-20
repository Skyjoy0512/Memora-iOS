import Foundation
import UIKit

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
}
