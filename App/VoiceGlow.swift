import SwiftUI

/// A sound-reactive, colorful glow that gathers along the bottom edge of its
/// container. Drive `level` with a 0...1 microphone amplitude.
struct VoiceGlow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// 0...1, how loud the voice is right now.
  var level: Double
  var isActive = true
  /// Up to seven lobe colours, laid out left to right.
  var colors: [Color] = VoiceGlow.rainbow

  static let rainbow: [Color] = [
    Color(red: 0.55, green: 0.30, blue: 0.96),
    Color(red: 0.34, green: 0.52, blue: 0.99),
    Color(red: 0.96, green: 0.42, blue: 0.72),
    Color(red: 0.99, green: 0.66, blue: 0.30),
    Color(red: 0.36, green: 0.86, blue: 0.74),
    Color(red: 0.62, green: 0.38, blue: 0.98)
  ]

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      if reduceMotion {
        glow(in: size, time: 0)
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
          glow(in: size, time: context.date.timeIntervalSinceReferenceDate)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func glow(in size: CGSize, time: Double) -> some View {
    let loudness = isActive ? max(0, min(1, level)) : 0
    let intensity = isActive ? 0.18 + 0.62 * loudness : 0
    let lobeWidth = max(size.width * 0.5, 40)

    return ZStack(alignment: .bottom) {
      ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
        let fraction = colors.count > 1 ? Double(index) / Double(colors.count - 1) : 0.5
        let swing = sin(time * 1.5 + Double(index) * 1.3) * 0.5 + 0.5
        let height = size.height * (0.16 + 0.46 * loudness) * (0.7 + 0.4 * swing)

        Ellipse()
          .fill(color)
          .frame(width: lobeWidth, height: height)
          .position(x: size.width * (0.06 + 0.88 * fraction), y: size.height)
          .blur(radius: max(size.height * 0.2, 14))
          .opacity(intensity)
      }

      // A brighter core so the middle blooms first.
      Ellipse()
        .fill(
          RadialGradient(
            colors: [.white.opacity(0.7), .white.opacity(0)],
            center: .bottom,
            startRadius: 0,
            endRadius: size.height * 0.6
          )
        )
        .frame(width: size.width * 0.36, height: size.height * (0.2 + 0.5 * loudness))
        .position(x: size.width / 2, y: size.height)
        .blur(radius: max(size.height * 0.16, 12))
        .opacity(intensity * 0.7)
    }
    .frame(width: size.width, height: size.height)
    .blendMode(.plusLighter)
  }
}
