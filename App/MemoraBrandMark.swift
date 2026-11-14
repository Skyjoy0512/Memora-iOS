import SwiftUI

/// The five-solid v3 mark. Its paths are shared with `MemoraThinkingLogo`.
struct MemoraBrandMark: View {
  var width: CGFloat = 144

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(MemoraBrandShape.allCases) { shape in
        MemoraBrandShapeView(shape: shape)
          .fill(MemoraBrandColor.primary)
      }
    }
    .frame(width: width, height: height)
  }

  private var height: CGFloat {
    width * MemoraBrandGeometry.markHeight / MemoraBrandGeometry.markWidth
  }
}

/// Maps one mark solid from the 432×92 space into the view's rect.
struct MemoraBrandShapeView: Shape {
  var shape: MemoraBrandShape

  func path(in rect: CGRect) -> Path {
    let scale = rect.width / MemoraBrandGeometry.markWidth
    return shape.path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
      tx: rect.minX, ty: rect.minY))
  }
}
