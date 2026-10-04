import SwiftUI

/// The coloured light that greets a list tab: a wash of the tab's own colour
/// across the top of the screen, drifting for a few seconds when the tab opens
/// and then holding still. Decoration only; it never takes touches and stands
/// still with Reduce Motion on.
struct TabTopGlow: View {
  var color: Color
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var startedAt: Date?
  @State private var isFlowing = false

  /// How long the wash drifts before it settles.
  private static let flowDuration: TimeInterval = 5

  var body: some View {
    TimelineView(.animation(paused: reduceMotion || !isFlowing)) { context in
      let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
      wash(t: reduceMotion ? 0 : min(elapsed, Self.flowDuration))
    }
    .mask {
      LinearGradient(
        stops: [
          .init(color: .black, location: 0),
          .init(color: .black, location: 0.12),
          .init(color: .clear, location: 0.55)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .opacity(colorScheme == .dark ? 0.28 : 0.38)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .ignoresSafeArea()
    .onAppear(perform: flow)
  }

  /// The colour holds at the top and thins out as the mesh's lower row reaches
  /// for the clear end of the mask.
  private func wash(t: TimeInterval) -> some View {
    MeshGradient(
      width: 3,
      height: 3,
      points: [
        [0, 0], [0.5, 0], [1, 0],
        [0, Float(0.16 + 0.08 * sin(t * 0.8))],
        [Float(0.5 + 0.2 * sin(t * 0.7)), Float(0.14 + 0.1 * cos(t * 0.9))],
        [1, Float(0.18 + 0.08 * cos(t * 0.6))],
        [0, 1], [0.5, 1], [1, 1]
      ],
      colors: [
        color.opacity(0.9), color.opacity(0.65), color.opacity(0.9),
        color.opacity(0.5), color.opacity(0.32), color.opacity(0.5),
        .clear, .clear, .clear
      ]
    )
  }

  /// Drifts for a few seconds after the tab opens, then stops.
  private func flow() {
    guard !reduceMotion else { return }
    startedAt = .now
    isFlowing = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(Self.flowDuration))
      isFlowing = false
    }
  }
}
