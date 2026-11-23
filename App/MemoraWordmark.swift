import SwiftUI

/// The outlined MEMORA wordmark from the supplied lockup, cropped to its ink.
struct MemoraWordmark: View {
  var width: CGFloat = 118
  var color: Color = MemoraBrandColor.primary

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(MemoraBrandGeometry.wordmarkPaths.enumerated()), id: \.offset) { _, path in
        MemoraWordmarkShape(path: path)
          .stroke(color, style: strokeStyle)
      }
    }
    .frame(width: width, height: height)
  }

  private var height: CGFloat {
    width * MemoraBrandGeometry.wordmarkBox.height / MemoraBrandGeometry.wordmarkBox.width
  }

  private var strokeStyle: StrokeStyle {
    StrokeStyle(lineWidth: MemoraBrandGeometry.wordmarkStrokeWidth * scale,
      lineCap: .square, lineJoin: .miter)
  }

  private var scale: CGFloat {
    width / MemoraBrandGeometry.wordmarkBox.width
  }
}

private struct MemoraWordmarkShape: Shape {
  var path: Path

  func path(in rect: CGRect) -> Path {
    let box = MemoraBrandGeometry.wordmarkBox
    let scale = rect.width / box.width
    return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
      tx: rect.minX - box.minX * scale, ty: rect.minY - box.minY * scale))
  }
}
