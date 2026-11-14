import SwiftUI

/// The mark breathing while Ask AI works: the five solids move apart by small
/// offsets and return to the exact static mark. The center circle stays calm.
struct MemoraThinkingLogo: View {
  var width: CGFloat = 36
  var isAnimating: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private var animates: Bool { isAnimating && !reduceMotion }
  private var height: CGFloat {
    width * MemoraBrandGeometry.markHeight / MemoraBrandGeometry.markWidth
  }

  var body: some View {
    ZStack {
      MemoraThinkingShapes(width: width, paused: !animates || scenePhase != .active)
        .opacity(animates ? 1 : 0)
      MemoraBrandMark(width: width)
        .opacity(animates ? 0 : 1)
    }
    .frame(width: width, height: height)
    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: animates)
    .accessibilityHidden(true)
  }
}

private struct MemoraThinkingShapes: View {
  var width: CGFloat
  var paused: Bool

  @State private var start = Date.now

  private static let loop: Double = 3
  private static let stagger: Double = 0.13

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 60, paused: paused)) { context in
      let elapsed = max(0, context.date.timeIntervalSince(start))
      let envelope = min(1, elapsed / 0.45)
      ZStack {
        ForEach(MemoraBrandShape.allCases) { shape in
          let motion = motion(for: shape, elapsed: elapsed, envelope: envelope)
          MemoraBrandShapeView(shape: shape)
            .fill(MemoraBrandColor.primary)
            .scaleEffect(motion.scale, anchor: shape.anchor)
            .rotationEffect(.degrees(motion.rotation), anchor: shape.anchor)
            .offset(y: motion.offset)
            .opacity(motion.opacity)
        }
      }
      .frame(width: width, height: width * MemoraBrandGeometry.markHeight / MemoraBrandGeometry.markWidth)
    }
    .onAppear { start = .now }
  }

  private func motion(for shape: MemoraBrandShape, elapsed: Double,
    envelope: Double) -> (offset: CGFloat, rotation: Double, scale: Double, opacity: Double) {
    let index = MemoraBrandShape.allCases.firstIndex(of: shape) ?? 0
    let phase = (elapsed - Double(index) * Self.stagger) / Self.loop
    let angle = phase * 2 * .pi
    let wave = sin(angle)
    let dip = 0.5 - 0.5 * cos(angle)

    // The center circle is the quiet core: it moves and fades least.
    if shape == .understand {
      return (CGFloat(0.8 * wave * envelope), 2 * wave * envelope,
        1 - 0.05 * dip * envelope, 1 - 0.2 * dip * envelope)
    }
    return (CGFloat(2.5 * wave * envelope), 7 * wave * envelope,
      1 - 0.13 * dip * envelope, 1 - 0.45 * dip * envelope)
  }
}
