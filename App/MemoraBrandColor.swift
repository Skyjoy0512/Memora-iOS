import SwiftUI

/// Brand ink follows the appearance the app already applies to its windows.
enum MemoraBrandColor {
  static let primary = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0xF6 / 255, green: 0xF4 / 255, blue: 0xEF / 255, alpha: 1)
      : UIColor(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255, alpha: 1)
  })
}
