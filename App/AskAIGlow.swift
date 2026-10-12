import SwiftUI

/// The light behind Ask AI, after Gemini: a glow rises from the bottom when
/// the tab opens, and a slowly moving wash of colour lights the top of the
/// screen while Memora is thinking, fading once the answer is in. It is decoration
/// only; it never takes touches and stands still with Reduce Motion on.
struct AskAIGlow: View {
  var isThinking: Bool
  var isEmpty: Bool
  /// Changes each time the tab opens, to replay the entrance.
  var entrance: Int
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @State private var isBlooming = false

  var body: some View {
    ZStack {
      // Opening the tab lights the bottom, under the composer; on the empty
      // screen a fainter glow stays there as an invitation to ask.
      LinearGradient(
        colors: [.clear, Self.blue.opacity(0.25), Self.blue.opacity(0.6)],
        startPoint: .init(x: 0.5, y: 0.45),
        endPoint: .bottom
      )
      .opacity(strength * (isBlooming ? 1 : (isEmpty ? 0.55 : 0)))

      // Thinking lights only the top, above the conversation.
      if isThinking {
        flowingWash
          .mask {
            LinearGradient(
              stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.55)],
              startPoint: .top,
              endPoint: .bottom
            )
          }
          .opacity(strength)
          .transition(.opacity)
      }
    }
    .opacity(reduceTransparency ? 0 : 1)
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
    colorScheme == .dark ? 0.12 : 0.1
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
          Self.teal.opacity(0.7), Self.blue.opacity(0.6), Self.blue.opacity(0.7),
          Self.yellow.opacity(0.5), Self.teal.opacity(0.35), Self.violet.opacity(0.45),
          .clear, .clear, .clear
        ]
      )
      .hueRotation(.degrees(18 * sin(t * 0.35)))
    }
  }

  /// Lights the screen for a moment, then lets it settle.
  private func bloom() {
    guard !reduceMotion else { return }
    withAnimation(.smooth(duration: 0.4)) { isBlooming = true }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(800))
      withAnimation(.smooth(duration: 1.2)) { isBlooming = false }
    }
  }

  // The agent keeps its existing motion; its light stays subordinate to text.
  private static let blue = MemoraPalette.textSecondary
  private static let teal = MemoraPalette.textSecondary
  private static let yellow = MemoraPalette.textPrimary
  private static let violet = MemoraPalette.textSecondary
}
