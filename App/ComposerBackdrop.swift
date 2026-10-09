import SwiftUI

struct ComposerBackdrop: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    Group {
      if reduceTransparency {
        Color(uiColor: .systemBackground)
      } else {
        Rectangle()
          .fill(.thinMaterial)
      }
    }
    .mask {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: .black.opacity(0.35), location: 0.25),
          .init(color: .black.opacity(0.85), location: 0.6),
          .init(color: .black, location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
