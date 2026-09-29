import SwiftUI

/// Draws text resolving the way it is read: each line lifts and sweeps in
/// from its leading edge a moment after the line above, so a paragraph reads
/// in instead of wiping in as one block. Reduce Motion never animates it, so
/// it only draws the complete text.
struct TextRevealRenderer: TextRenderer {
  /// Runs linearly from 0 to 1; each line applies its own easing, so the
  /// stagger between lines does not squash the curve of any one of them.
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  /// Room for the rise, which would otherwise be clipped at the
  /// text's bounds.
  var displayPadding: EdgeInsets {
    EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    guard progress < 1 else {
      for line in layout { context.draw(line) }
      return
    }

    let lineCount = layout.count
    // Later lines start a little behind earlier ones, but a long paragraph
    // shares a fixed budget so it does not take longer than a heading.
    let spread = lineCount > 1 ? min(0.45, 0.12 * Double(lineCount - 1)) : 0

    for (index, line) in layout.enumerated() {
      let start = lineCount > 1 ? spread * Double(index) / Double(lineCount - 1) : 0
      let local = min(1, max(0, (progress - start) / (1 - spread)))
      if local <= 0 { continue }
      if local >= 1 {
        context.draw(line)
      } else {
        draw(line, at: local, in: context)
      }
    }
  }

  private func draw(_ line: Text.Layout.Line, at local: Double, in context: GraphicsContext) {
    let eased = 1 - pow(1 - local, 3)
    let bounds = line.typographicBounds.rect
    let softEdge = max(32, bounds.width * 0.35)
    let front = (bounds.width + softEdge) * eased

    // Opacity and a small rise only: a blur needs an offscreen layer per line
    // on every frame, which made screens stutter.
    var lineContext = context
    lineContext.translateBy(x: 0, y: (1 - eased) * 6)
    for run in line {
      let isRightToLeft = run.layoutDirection == .rightToLeft
      for slice in run {
        let rect = slice.typographicBounds.rect
        let distance = isRightToLeft ? bounds.maxX - rect.maxX : rect.minX - bounds.minX
        let alpha = min(1, max(0, (front - distance) / softEdge))
        guard alpha > 0 else { continue }
        var glyph = lineContext
        glyph.opacity = alpha
        glyph.draw(slice)
      }
    }
  }
}
