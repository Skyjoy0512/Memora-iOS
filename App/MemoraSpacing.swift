import SwiftUI

/// Native point values; the shared rhythm follows the official four-unit grid.
enum MemoraSpacing {
  static let xxs: CGFloat = 2
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 20
  static let xxl: CGFloat = 24
  static let section: CGFloat = 32
  static let group: CGFloat = 40
  static let page: CGFloat = 48
  static let screen = xl
  static let card = lg
  static let row = md
  static let touchTarget: CGFloat = 44
  static let readingWidth: CGFloat = 680
}
