import SwiftUI

/// A SwiftUI interpretation of the luminous, layered iOS 9 Siri waveform.
struct SiriWaveView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var isPaused = false

  var body: some View {
    Group {
      if reduceMotion || isPaused {
        waves(at: 0)
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
          waves(at: context.date.timeIntervalSinceReferenceDate)
        }
      }
    }
    .opacity(isPaused ? 0.38 : 1)
    .animation(.smooth, value: isPaused)
    .accessibilityHidden(true)
  }

  private func waves(at time: TimeInterval) -> some View {
    Canvas { context, size in
      let layers: [(Color, Double, Double, CGFloat)] = [
        (.primary.opacity(0.26), 1.15, 0, 1),
        (.blue.opacity(0.78), 1.38, 0.6, 1.6),
        (.pink.opacity(0.72), 1.12, 2.2, 1.45),
        (.mint.opacity(0.72), 1.55, 4.1, 1.35)
      ]

      context.addFilter(.blur(radius: 0.35))
      for layer in layers {
        var path = Path()
        let step: CGFloat = 2
        for x in stride(from: CGFloat.zero, through: size.width, by: step) {
          let normalized = x / max(size.width, 1)
          let envelope = pow(sin(.pi * normalized), 2.2)
          let carrier = sin(normalized * .pi * 4.4 + time * layer.1 + layer.2)
          let shimmer = sin(normalized * .pi * 9.2 - time * 0.7 + layer.2) * 0.24
          let y = size.height / 2 + (carrier + shimmer) * size.height * 0.28 * envelope
          if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(layer.0), style: StrokeStyle(lineWidth: layer.3, lineCap: .round))
      }
    }
    .drawingGroup()
  }
}
