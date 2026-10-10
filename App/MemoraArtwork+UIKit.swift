import UIKit

extension MemoraArtwork {
  @MainActor
  func image(size: CGFloat) -> UIImage? {
    guard let image = UIImage(named: rawValue) else { return nil }
    let dimensions = CGSize(width: size, height: size)
    return UIGraphicsImageRenderer(size: dimensions).image { _ in
      image.draw(in: CGRect(origin: .zero, size: dimensions))
    }.withRenderingMode(.alwaysTemplate)
  }
}
