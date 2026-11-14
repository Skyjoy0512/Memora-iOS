import SwiftUI

/// One solid from the supplied v3 mark, in its 432×92 coordinate space.
/// The static mark and the thinking animation draw from this same definition.
enum MemoraBrandShape: String, CaseIterable, Identifiable {
  case record
  case organize
  case understand
  case connect
  case expand

  var id: String { rawValue }

  var path: Path {
    switch self {
    case .record:
      var path = Path()
      path.addRect(CGRect(x: 0, y: 2, width: 68, height: 88))
      return path

    case .organize:
      var path = Path()
      path.move(to: CGPoint(x: 80, y: 2))
      path.addLine(to: CGPoint(x: 82, y: 2))
      var arc = Path()
      arc.addArc(center: .zero, radius: 1,
        startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
      path.addPath(arc.applying(CGAffineTransform(a: 50, b: 0, c: 0, d: 44, tx: 82, ty: 46)))
      path.addLine(to: CGPoint(x: 80, y: 90))
      path.closeSubpath()
      return path

    case .understand:
      return Path(ellipseIn: CGRect(x: 144, y: 0, width: 92, height: 92))

    case .connect:
      var path = Path()
      path.move(to: CGPoint(x: 249, y: 2))
      path.addLine(to: CGPoint(x: 333, y: 2))
      path.addLine(to: CGPoint(x: 333, y: 90))
      path.addLine(to: CGPoint(x: 311, y: 90))
      path.addCurve(to: CGPoint(x: 249, y: 40),
        control1: CGPoint(x: 308, y: 60),
        control2: CGPoint(x: 282, y: 40))
      path.closeSubpath()
      return path

    case .expand:
      var path = Path()
      path.move(to: CGPoint(x: 345, y: 2))
      path.addLine(to: CGPoint(x: 432, y: 90))
      path.addLine(to: CGPoint(x: 345, y: 90))
      path.closeSubpath()
      return path
    }
  }

  var center: CGPoint {
    switch self {
    case .record: CGPoint(x: 34, y: 46)
    case .organize: CGPoint(x: 106, y: 46)
    case .understand: CGPoint(x: 190, y: 46)
    case .connect: CGPoint(x: 291, y: 46)
    case .expand: CGPoint(x: 388.5, y: 46)
    }
  }

  var anchor: UnitPoint {
    UnitPoint(x: center.x / MemoraBrandGeometry.markWidth,
      y: center.y / MemoraBrandGeometry.markHeight)
  }
}
