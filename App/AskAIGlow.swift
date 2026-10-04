import SwiftUI

/// The light behind Ask AI, after Gemini: a soft glow rises from the bottom
/// when the tab opens, and a slowly moving wash of colour fills the screen
/// while Memora is thinking, fading once the answer is in. It is decoration
/// only; it never takes touches and stands still with Reduce Motion on.
struct AskAIGlow: View {
  var isThinking: Bool
  var isEmpty: Bool
  /// Changes each time the tab opens, to replay the entrance.
  var entrance: Int
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isBlooming = false

  var body: some View {
    ZStack {
      // At rest, the empty screen keeps a faint glow at the bottom, under the
      // composer, as an invitation to ask.
      LinearGradient(
        colors: [.clear, Self.blue.opacity(strength * 0.35)],
        startPoint: .center,
        endPoint: .bottom
      )
      .opacity(isEmpty ? 1 : 0)

      if isThinking || isBlooming {
        flowingWash
          .opacity(isThinking ? strength : (isBlooming ? strength * 0.8 : 0))
          .transition(.opacity)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .ignoresSafeArea()
    .animation(.smooth(duration: 0.9), value: isThinking)
    .animation(.smooth(duration: 0.6), value: isEmpty)
    .onAppear(perform: bloom)
    .onChange(of: entrance) { _, _ in bloom() }
  }

  /// Dark mode needs less colour to read as the same glow.
  private var strength: Double {
    colorScheme == .dark ? 0.55 : 1
  }

  private var flowingWash: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
      MeshGradient(
        width: 3,
        height: 3,
        points: [
          [0, 0], [0.5, 0], [1, 0],
          [0, Float(0.45 + 0.1 * sin(t * 0.7))],
          [Float(0.5 + 0.18 * sin(t * 0.9)), Float(0.45 + 0.12 * cos(t * 0.8))],
          [1, Float(0.5 + 0.1 * cos(t * 0.6))],
          [0, 1], [0.5, 1], [1, 1]
        ],
        colors: [
          Self.teal.opacity(0.55), Self.blue.opacity(0.5), Self.blue.opacity(0.6),
          Self.yellow.opacity(0.4), Self.teal.opacity(0.25), Self.violet.opacity(0.35),
          .clear, .clear, Self.blue.opacity(0.15)
        ]
      )
      .hueRotation(.degrees(18 * sin(t * 0.35)))
    }
  }

  /// Lights the screen for a moment, then lets it settle.
  private func bloom() {
    guard !reduceMotion else { return }
    withAnimation(.smooth(duration: 0.35)) { isBlooming = true }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(700))
      withAnimation(.smooth(duration: 1.2)) { isBlooming = false }
    }
  }

  private static let blue = Color(red: 0.33, green: 0.55, blue: 0.98)
  private static let teal = Color(red: 0.35, green: 0.8, blue: 0.85)
  private static let yellow = Color(red: 0.98, green: 0.9, blue: 0.55)
  private static let violet = Color(red: 0.62, green: 0.55, blue: 0.98)
}
