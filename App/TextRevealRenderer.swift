import SwiftUI

/// A brief line fade keeps the final layout fixed and costs one draw per line.
struct TextRevealRenderer: TextRenderer {
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    guard progress < 1 else {
      for line in layout { context.draw(line) }
      return
    }
    let spread = layout.count > 1 ? 0.18 : 0
    for (index, line) in layout.enumerated() {
      let start = spread * Double(index) / Double(max(1, layout.count - 1))
      let fraction = min(1, max(0, (progress - start) / (1 - spread)))
      guard fraction > 0 else { continue }
      var lineContext = context
      lineContext.opacity *= fraction * fraction * (3 - 2 * fraction)
      lineContext.draw(line)
    }
  }
}
