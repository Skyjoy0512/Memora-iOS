import SwiftUI

/// The supplied combination logo: the v3 mark above the outlined wordmark.
struct MemoraBrandLockup: View {
  var width: CGFloat = 144

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(MemoraBrandShape.allCases) { shape in
        MemoraBrandShapeView(shape: shape)
          .fill(MemoraBrandColor.primary)
      }
      ForEach(Array(MemoraBrandGeometry.wordmarkPaths.enumerated()), id: \.offset) { _, path in
        MemoraLockupWordmarkShape(path: path)
          .stroke(MemoraBrandColor.primary, style: strokeStyle)
      }
    }
    .frame(width: width, height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Memora")
  }

  private var height: CGFloat {
    width * MemoraBrandGeometry.lockupHeight / MemoraBrandGeometry.markWidth
  }

  private var scale: CGFloat {
    width / MemoraBrandGeometry.markWidth
  }

  private var strokeStyle: StrokeStyle {
    StrokeStyle(lineWidth: MemoraBrandGeometry.wordmarkStrokeWidth * scale,
      lineCap: .square, lineJoin: .miter)
  }
}

/// Maps a wordmark stroke from the lockup canvas into the view's rect.
private struct MemoraLockupWordmarkShape: Shape {
  var path: Path

  func path(in rect: CGRect) -> Path {
    let scale = rect.width / MemoraBrandGeometry.markWidth
    return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
      tx: rect.minX, ty: rect.minY))
  }
}
