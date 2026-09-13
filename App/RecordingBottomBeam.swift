import SwiftUI

/// A traveling glow at the physical bottom edge while recording is live.
struct RecordingBottomBeam: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      if reduceMotion {
        beam(in: proxy.size, progress: 0.5)
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
          beam(
            in: proxy.size,
            progress: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
          )
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .ignoresSafeArea()
  }

  private func beam(in size: CGSize, progress: Double) -> some View {
    let beamWidth: CGFloat = 180
    let x = (size.width + beamWidth) * progress - beamWidth

    return Capsule()
      .fill(
        LinearGradient(
          colors: [.clear, .cyan, .blue, .purple, .pink, .clear],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .frame(width: beamWidth, height: 3)
      .shadow(color: .purple.opacity(0.65), radius: 7)
      .shadow(color: .cyan.opacity(0.5), radius: 11)
      .position(x: x + beamWidth / 2, y: size.height - 1)
  }
}
