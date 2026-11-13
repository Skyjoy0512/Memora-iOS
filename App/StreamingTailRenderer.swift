import SwiftUI

/// Draws settled lines in one operation; at most eight small tail ranges animate.
struct StreamingTailRenderer: TextRenderer {
  var visibleCharacters: Double

  var animatableData: Double {
    get { visibleCharacters }
    set { visibleCharacters = newValue }
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for line in layout {
      let isSettled = line.allSatisfy { run in
        guard let range = run[StreamingTailRange.self] else { return true }
        return visibleCharacters >= Double(range.range.upperBound)
      }
      if isSettled {
        context.draw(line)
        continue
      }
      for run in line {
        var runContext = context
        if let range = run[StreamingTailRange.self] {
          runContext.opacity *= StreamingTextTail.opacity(visibleCharacters: visibleCharacters, range: range.range)
        }
        runContext.draw(run)
      }
    }
  }
}

/// Character offsets refer to the parsed attributed text, preserving composed
/// characters, emphasis and citation URLs when the tail is divided into ranges.
struct StreamingTailRange: TextAttribute {
  var range: Range<Int>
}
