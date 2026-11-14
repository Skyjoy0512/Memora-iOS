import SwiftUI

/// The supplied v3 artwork in its original coordinate spaces. The mark is
/// 432×92; the lockup adds the outlined wordmark below it in a 432×134 canvas.
enum MemoraBrandGeometry {
  static let markWidth: CGFloat = 432
  static let markHeight: CGFloat = 92
  static let lockupHeight: CGFloat = 134
  static let wordmarkStrokeWidth: CGFloat = 1.65
  /// Tight bounds around the outlined wordmark inside the lockup canvas.
  static let wordmarkBox = CGRect(x: 78, y: 112.5, width: 271, height: 21)

  static let wordmarkPaths: [Path] = {
    var paths: [Path] = []

    var firstM = Path()
    firstM.move(to: CGPoint(x: 79, y: 132))
    firstM.addLine(to: CGPoint(x: 79, y: 114))
    firstM.addLine(to: CGPoint(x: 89, y: 127))
    firstM.addLine(to: CGPoint(x: 99, y: 114))
    firstM.addLine(to: CGPoint(x: 99, y: 132))
    paths.append(firstM)

    var e = Path()
    e.move(to: CGPoint(x: 147, y: 114))
    e.addLine(to: CGPoint(x: 134, y: 114))
    e.addLine(to: CGPoint(x: 134, y: 132))
    e.addLine(to: CGPoint(x: 147, y: 132))
    e.move(to: CGPoint(x: 134, y: 123))
    e.addLine(to: CGPoint(x: 145, y: 123))
    paths.append(e)

    var secondM = Path()
    secondM.move(to: CGPoint(x: 180, y: 132))
    secondM.addLine(to: CGPoint(x: 180, y: 114))
    secondM.addLine(to: CGPoint(x: 190, y: 127))
    secondM.addLine(to: CGPoint(x: 200, y: 114))
    secondM.addLine(to: CGPoint(x: 200, y: 132))
    paths.append(secondM)

    paths.append(Path(ellipseIn: CGRect(x: 232.5, y: 113.5, width: 19, height: 19)))

    var r = Path()
    r.move(to: CGPoint(x: 284, y: 132))
    r.addLine(to: CGPoint(x: 284, y: 114))
    r.addLine(to: CGPoint(x: 292, y: 114))
    r.addCurve(to: CGPoint(x: 292, y: 125),
      control1: CGPoint(x: 302, y: 114),
      control2: CGPoint(x: 302, y: 125))
    r.addLine(to: CGPoint(x: 284, y: 125))
    r.move(to: CGPoint(x: 291, y: 125))
    r.addLine(to: CGPoint(x: 300, y: 132))
    paths.append(r)

    var a = Path()
    a.move(to: CGPoint(x: 330, y: 132))
    a.addLine(to: CGPoint(x: 339, y: 114))
    a.addLine(to: CGPoint(x: 348, y: 132))
    a.move(to: CGPoint(x: 333, y: 126))
    a.addLine(to: CGPoint(x: 345, y: 126))
    paths.append(a)

    return paths
  }()
}
