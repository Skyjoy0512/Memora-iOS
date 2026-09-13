import SwiftUI

/// A quiet, native Border Beam interpretation for the few moments where the
/// app is actively listening or thinking.
struct MemoraBorderBeam: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var cornerRadius: CGFloat
  var strength: Double = 0.7
  var active = true

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(Color.primary.opacity(0.1), lineWidth: 0.75)

      if active {
        if reduceMotion {
          beam(progress: 0.12)
        } else {
          TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            beam(progress: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6)
          }
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func beam(progress: Double) -> some View {
    let length = 0.2
    let end = progress + length

    return ZStack {
      segment(from: progress, to: min(end, 1))
      if end > 1 {
        segment(from: 0, to: end - 1)
      }
    }
  }

  private func segment(from start: Double, to end: Double) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .trim(from: start, to: end)
      .stroke(
        LinearGradient(
          colors: [.cyan, .blue, .purple, .pink, .orange],
          startPoint: .leading,
          endPoint: .trailing
        ),
        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
      )
      .shadow(color: .purple.opacity(strength * 0.45), radius: 4)
      .shadow(color: .cyan.opacity(strength * 0.35), radius: 7)
  }
}
