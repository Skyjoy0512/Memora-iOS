import Foundation

/// Small vector vocabulary shared by native preview, PDF and editable DrawingML.
struct PresentationElement: Hashable, Sendable, Identifiable {
  var id: Int
  var kind: Kind
  var x: Double
  var y: Double
  var width: Double
  var height: Double
  var text = ""
  var fontSize = 20.0
  var fontName = PresentationTheme.font
  var latinFontName: String?
  var bold = false
  var color = PresentationTheme.ink
  var fill: String?
  var points: [Point] = []
  /// Decorations may intentionally contain labels or connect adjacent shapes.
  var checksCollision = true

  enum Kind: String, Hashable, Sendable { case text, rectangle, ellipse, polygon, line }
  struct Point: Hashable, Sendable { var x: Double; var y: Double }

  var maxX: Double { x + width }
  var maxY: Double { y + height }
}
