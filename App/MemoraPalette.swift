import SwiftUI
import UIKit

/// Content colors adapt independently of the system's floating glass layer.
enum MemoraPalette {
  static let background = adaptive(light: 0xFFFFFF, dark: 0x212121)
  static let secondaryBackground = adaptive(light: 0xF9F9F9, dark: 0x181818)
  static let card = adaptive(light: 0xF3F3F3, dark: 0x303030)
  static let elevated = adaptive(light: 0xFFFFFF, dark: 0x303030)
  static let textPrimary = adaptive(light: 0x0D0D0D, dark: 0xFFFFFF)
  static let textSecondary = adaptive(light: 0x5D5D5D, dark: 0xAFAFAF,
    increasedLight: 0x525252, increasedDark: 0xD4D4D4)
  static let cardTextSecondary = textSecondary
  static let border = adaptive(light: 0xE5E5E5, dark: 0x353535,
    increasedLight: 0xA3A3A3, increasedDark: 0x737373)
  static let action = textPrimary
  static let actionLabel = adaptive(light: 0xFFFFFF, dark: 0x0D0D0D)
  static let selection = adaptive(light: 0xEDEDED, dark: 0x414141)
  static let focus = adaptive(light: 0x0169CC, dark: 0x339CFF)
  static let danger = adaptive(light: 0xBA2623, dark: 0xFF908E)
  static let warning = adaptive(light: 0x923B0F, dark: 0xFF9E6C)
  static let success = adaptive(light: 0x00692A, dark: 0x66D492)

  private static func adaptive(light: UInt32, dark: UInt32,
    increasedLight: UInt32? = nil, increasedDark: UInt32? = nil) -> Color {
    Color(uiColor: UIColor { traits in
      let isDark = traits.userInterfaceStyle == .dark
      let increased = traits.accessibilityContrast == .high
      let hex = isDark ? (increased ? increasedDark ?? dark : dark)
        : (increased ? increasedLight ?? light : light)
      return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    })
  }
}
