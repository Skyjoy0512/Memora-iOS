import SwiftUI

/// Lays subviews out left to right, wrapping to the next line like text. Used
/// so each word of a streamed answer can animate on its own.
struct FlowLayout: Layout {
  var spacing: CGFloat = 0
  var lineSpacing: CGFloat = 0

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var lineWidth: CGFloat = 0
    var lineHeight: CGFloat = 0
    var totalHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if lineWidth > 0, lineWidth + size.width > maxWidth {
        totalHeight += lineHeight + lineSpacing
        lineWidth = 0
        lineHeight = 0
      }
      lineWidth += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    totalHeight += lineHeight

    return CGSize(width: maxWidth.isFinite ? maxWidth : lineWidth, height: totalHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    var x = bounds.minX
    var y = bounds.minY
    var lineHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += lineHeight + lineSpacing
        lineHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}
