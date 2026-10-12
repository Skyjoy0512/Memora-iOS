import SwiftUI
import UIKit

/// Content colors adapt independently of the system's floating glass layer.
enum MemoraPalette {
  static let background = adaptive(light: 0xFFFFFF, dark: 0x0B0B0B)
  static let secondaryBackground = adaptive(light: 0xF7F7F7, dark: 0x171717)
  static let card = adaptive(light: 0xF5F5F5, dark: 0x202020)
  static let textPrimary = adaptive(light: 0x0B0B0B, dark: 0xFFFFFF)
  static let textSecondary = adaptive(light: 0x737373, dark: 0xA3A3A3,
    increasedLight: 0x525252, increasedDark: 0xD4D4D4)
  // Slightly stronger on F5 cards so small metadata clears 4.5:1 contrast.
  static let cardTextSecondary = adaptive(light: 0x707070, dark: 0xA3A3A3,
    increasedLight: 0x525252, increasedDark: 0xD4D4D4)
  static let border = adaptive(light: 0xE5E5E5, dark: 0x353535,
    increasedLight: 0xA3A3A3, increasedDark: 0x737373)
  static let action = textPrimary
  static let actionLabel = adaptive(light: 0xFFFFFF, dark: 0x0B0B0B)

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
