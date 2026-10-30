import UIKit

extension MemoraArtwork {
  @MainActor
  func image(size: CGFloat) -> UIImage? {
    UIImage(icon: icon, size: size)?.withRenderingMode(.alwaysTemplate)
  }
}
