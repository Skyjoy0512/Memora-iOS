import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum PhotoAspect: String, CaseIterable, Identifiable {
  case original
  case square
  case wide

  var id: Self { self }

  var label: String {
    switch self {
    case .original: "オリジナル"
    case .square: "正方形"
    case .wide: "16:9"
    }
  }

  func ratio(for imageSize: CGSize?) -> CGFloat {
    switch self {
    case .original:
      guard let imageSize, imageSize.height > 0 else { return 1 }
      return imageSize.width / imageSize.height
    case .square:
      return 1
    case .wide:
      return 16.0 / 9.0
    }
  }
}
