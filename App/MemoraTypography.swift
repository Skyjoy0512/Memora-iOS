import SwiftUI

/// Roles scale with the system; the point sizes documented in DESIGN are defaults.
enum MemoraTypography {
  static let display: Font = .largeTitle.weight(.semibold)
  static let screenTitle: Font = .title.weight(.semibold)
  static let sectionHeading: Font = .title3.weight(.semibold)
  static let body: Font = .body
  static let readingBody: Font = .body
  static let secondary: Font = .subheadline
  static let caption: Font = .caption
  static let metadata: Font = .footnote
  static let readingLineSpacing: CGFloat = 6
  static let paragraphSpacing = MemoraSpacing.lg
  static let listIndent = MemoraSpacing.xl

  static func heading(_ level: Int) -> Font {
    switch level {
    case 1: .title2.weight(.semibold)
    case 2: sectionHeading
    default: .headline
    }
  }
}
