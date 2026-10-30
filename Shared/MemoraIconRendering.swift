import CoreGraphics
import CoreText
import Foundation
import LucideSwift
import SwiftUI

/// One template renderer for SwiftUI, UIKit and widgets. Stroke thickness
/// follows Lucide's 24-point grid instead of becoming heavy at small sizes.
enum MemoraIconRendering {
  static let scale: CGFloat = 3

  static func image(_ icon: MemoraIcon, size: CGFloat) -> CGImage? {
    guard size.isFinite, size > 0, size <= 256 else { return nil }
    let pixels = max(1, Int((size * scale).rounded(.up)))
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
      bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    context.setShouldAntialias(true)
    context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    context.setLineWidth(size * 2 / 24)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let path = icon.lucideName.shape.path(in: CGRect(x: 0, y: 0, width: size, height: size))
    context.addPath(path.cgPath)
    context.strokePath()
    if icon == .gobackward15 || icon == .goforward15 {
      // Lucide's rotation glyph supplies the shape; the transport's actual
      // skip interval stays visible, rather than looking like restart/next.
      let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size * 0.33, nil)
      let label = NSAttributedString(string: "15", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
      ])
      let line = CTLineCreateWithAttributedString(label)
      let width = CTLineGetTypographicBounds(line, nil, nil, nil)
      context.saveGState()
      context.translateBy(x: (size - width) / 2, y: size * 0.64)
      context.scaleBy(x: 1, y: -1)
      context.textPosition = .zero
      CTLineDraw(line, context)
      context.restoreGState()
    }
    return context.makeImage()
  }
}
