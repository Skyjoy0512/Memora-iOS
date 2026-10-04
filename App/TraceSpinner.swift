import SwiftUI

/// A thin ring turning, for a step still running: lighter than the system
/// spinner, so it sits with the muted checks around it. Reduce Motion keeps it
/// still.
struct TraceSpinner: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isTurning = false

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.72)
      .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
      .frame(width: 11, height: 11)
      .rotationEffect(.degrees(isTurning ? 360 : 0))
      .animation(reduceMotion ? nil : .linear(duration: 0.7).repeatForever(autoreverses: false), value: isTurning)
      .onAppear { isTurning = true }
      .accessibilityHidden(true)
  }
}
