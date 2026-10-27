import CoreGraphics
import CoreText
import Foundation

enum PresentationDrawing {
  /// The caller provides top-left coordinates, including when drawing into a PDF context.
  static func draw(_ elements: [PresentationElement], in context: CGContext) {
    for e in elements {
      context.saveGState()
      context.setStrokeColor(color(e.color)); context.setLineWidth(1)
      context.setFillColor(color(e.fill ?? e.color))
      let rect = CGRect(x: e.x, y: e.y, width: e.width, height: e.height)
      switch e.kind {
      case .rectangle: context.fill(rect)
      case .ellipse: context.fillEllipse(in: rect)
      case .line, .polygon:
        if let first = e.points.first {
          context.move(to: CGPoint(x: first.x, y: first.y))
          for point in e.points.dropFirst() { context.addLine(to: CGPoint(x: point.x, y: point.y)) }
          if e.kind == .polygon { context.closePath(); context.fillPath() } else { context.strokePath() }
        }
      case .text:
        let font = PresentationText.font(size: e.fontSize, bold: e.bold)
        for (i, text) in PresentationText.lines(e).enumerated() {
          let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(e.color)
          ]))
          context.saveGState()
          context.translateBy(x: e.x, y: e.y + Double(i) * e.fontSize * 1.3 + e.fontSize)
          context.scaleBy(x: 1, y: -1)
          context.textPosition = .zero
          CTLineDraw(line, context)
          context.restoreGState()
        }
      }
      context.restoreGState()
    }
  }

  static func color(_ hex: String) -> CGColor {
    let value = UInt32(hex, radix: 16) ?? 0x171717
    return CGColor(red: Double((value >> 16) & 255) / 255,
                   green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
  }
}
