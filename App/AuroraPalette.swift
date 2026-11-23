// Portions derived from Google ADK Recipes, Copyright 2026 Google LLC.
// Adapted for Memora: SwiftUI colors, adjusted light and dark opacities.
// Licensed under Apache-2.0. See Resources/GoogleADKRecipes-LICENSE.txt.

import SwiftUI

struct AuroraPalette {
  var center: Gradient
  var left: Gradient
  var right: Gradient
  var ice: Gradient

  static let light = Self(strength: 1)
  static let dark = Self(strength: 0.63)

  private init(strength: Double) {
    center = Self.gradient(inner: 0x1D4ED8, mid: 0x1E3A8A, innerAlpha: 0.30, midAlpha: 0.11, strength: strength)
    left = Self.gradient(inner: 0x2563EB, mid: 0x1D4ED8, innerAlpha: 0.26, midAlpha: 0.11, strength: strength)
    right = Self.gradient(inner: 0x38BDF8, mid: 0x3B82F6, innerAlpha: 0.39, midAlpha: 0.17, strength: strength)
    ice = Self.gradient(inner: 0xBAE6FD, mid: 0x60A5FA, innerAlpha: 0.42, midAlpha: 0.18, strength: strength)
  }

  private static func gradient(inner: UInt32, mid: UInt32, innerAlpha: Double, midAlpha: Double, strength: Double) -> Gradient {
    Gradient(stops: [
      .init(color: rgb(inner).opacity(innerAlpha * strength), location: 0),
      .init(color: rgb(mid).opacity(midAlpha * strength), location: 0.52),
      .init(color: rgb(0x0F172A).opacity(0), location: 1)
    ])
  }

  private static func rgb(_ hex: UInt32) -> Color {
    Color(red: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
  }
}
