import SwiftUI

/// A layered radial gradient, seeded so a card keeps the same look across
/// launches. In the spirit of OpenAI's random gradients: a soft base with two
/// or three colored blooms at random points.
struct SeededGradient: View {
  @Environment(\.colorScheme) private var colorScheme
  var seed: UUID

  var body: some View {
    GeometryReader { proxy in
      let maxDimension = max(proxy.size.width, proxy.size.height)
      let spec = Self.spec(seed: seed, dark: colorScheme == .dark)

      ZStack {
        spec.base

        ForEach(spec.blooms) { bloom in
          RadialGradient(
            colors: [bloom.color.opacity(bloom.opacity), bloom.color.opacity(0)],
            center: bloom.center,
            startRadius: 0,
            endRadius: maxDimension * bloom.radius
          )
          .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        }
      }
    }
    .accessibilityHidden(true)
  }

  private struct Bloom: Identifiable {
    var id: Int
    var color: Color
    var center: UnitPoint
    var radius: CGFloat
    var opacity: Double
  }

  private struct Spec {
    var base: Color
    var blooms: [Bloom]
  }

  private static func spec(seed: UUID, dark: Bool) -> Spec {
    var rng = SeededGenerator(seed: seedValue(seed))
    let palette = dark ? darkPalette : lightPalette
    let count = Int.random(in: 2...3, using: &rng)

    var blooms: [Bloom] = []
    var used: Set<Int> = []

    for index in 0..<count {
      var colorIndex = Int.random(in: 0..<palette.count, using: &rng)
      while used.contains(colorIndex), used.count < palette.count {
        colorIndex = (colorIndex + 1) % palette.count
      }
      used.insert(colorIndex)

      blooms.append(
        Bloom(
          id: index,
          color: palette[colorIndex],
          center: UnitPoint(
            x: CGFloat.random(in: 0.05...0.95, using: &rng),
            y: CGFloat.random(in: 0.05...0.95, using: &rng)
          ),
          radius: CGFloat.random(in: 0.55...1.05, using: &rng),
          opacity: dark
            ? Double.random(in: 0.35...0.6, using: &rng)
            : Double.random(in: 0.45...0.7, using: &rng)
        )
      )
    }

    return Spec(base: dark ? Color(white: 0.10) : Color(white: 0.97), blooms: blooms)
  }

  private static func seedValue(_ id: UUID) -> UInt64 {
    var value: UInt64 = 0
    withUnsafeBytes(of: id.uuid) { bytes in
      for index in 0..<8 {
        value = (value << 8) | UInt64(bytes[index])
      }
    }
    return value
  }

  private static let lightPalette: [Color] = [
    Color(red: 0.99, green: 0.62, blue: 0.72),
    Color(red: 1.00, green: 0.78, blue: 0.55),
    Color(red: 0.98, green: 0.90, blue: 0.55),
    Color(red: 0.60, green: 0.90, blue: 0.72),
    Color(red: 0.56, green: 0.80, blue: 1.00),
    Color(red: 0.72, green: 0.66, blue: 1.00),
    Color(red: 0.99, green: 0.66, blue: 0.55)
  ]

  private static let darkPalette: [Color] = [
    Color(red: 0.60, green: 0.20, blue: 0.45),
    Color(red: 0.70, green: 0.36, blue: 0.20),
    Color(red: 0.20, green: 0.45, blue: 0.65),
    Color(red: 0.22, green: 0.55, blue: 0.42),
    Color(red: 0.40, green: 0.28, blue: 0.70),
    Color(red: 0.55, green: 0.28, blue: 0.30)
  ]
}

/// A tiny deterministic generator so a seed always yields the same gradient.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed &+ 0x9E37_79B9_7F4A_7C15
  }

  mutating func next() -> UInt64 {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
