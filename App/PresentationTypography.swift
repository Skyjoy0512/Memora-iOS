import Foundation

/// The presentation's own type scale. It is independent of the app's Dynamic
/// Type: a deck keeps its proportions when rendered to PDF or PowerPoint.
enum PresentationTypography {
  enum Weight: String, Sendable {
    case regular, semibold, bold
    var isBold: Bool { self != .regular }
  }

  struct Style: Sendable {
    var size: Double
    var weight: Weight
    var lineHeight: Double
    var tracking: Double = 0
    var role: Role

    enum Role: Sendable { case title, message, heading, body, label, number, unit, note, source, pageNumber }
  }

  /// 16:9 at 960 × 540 points. The scale follows the content hierarchy rather
  /// than the screen: one title, one message line, then supporting text.
  static let coverTitle = Style(size: 42, weight: .bold, lineHeight: 56, tracking: -0.5, role: .title)
  static let slideTitle = Style(size: 30, weight: .bold, lineHeight: 40, tracking: -0.2, role: .title)
  static let sectionTitle = Style(size: 40, weight: .bold, lineHeight: 52, tracking: -0.4, role: .title)
  static let message = Style(size: 22, weight: .semibold, lineHeight: 30, role: .message)
  static let heading = Style(size: 22, weight: .bold, lineHeight: 30, role: .heading)
  static let body = Style(size: 19, weight: .regular, lineHeight: 28, role: .body)
  static let label = Style(size: 17, weight: .semibold, lineHeight: 24, role: .label)
  static let number = Style(size: 56, weight: .bold, lineHeight: 68, tracking: -1, role: .number)
  static let smallNumber = Style(size: 38, weight: .bold, lineHeight: 48, tracking: -0.6, role: .number)
  static let unit = Style(size: 18, weight: .semibold, lineHeight: 24, role: .unit)
  static let note = Style(size: 14, weight: .regular, lineHeight: 20, role: .note)
  static let source = Style(size: 10, weight: .regular, lineHeight: 14, role: .source)
  static let pageNumber = Style(size: 10, weight: .regular, lineHeight: 14, role: .pageNumber)
}

/// A 12-column grid over the 960 × 540 canvas, with margins that leave room for
/// notes and sources at the bottom.
enum PresentationGrid {
  static let margin = 54.0
  static let contentWidth = 852.0
  static let columnGutter = 24.0
  static let titleTop = 28.0
  static let bodyTop = 154.0
  static let footerTop = 504.0
  static let cardRadiusHint = 0.0

  static func columnWidth(_ columns: Int) -> Double {
    guard columns > 0 else { return contentWidth }
    return (contentWidth - Double(columns - 1) * columnGutter) / Double(columns)
  }
}
