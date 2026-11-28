import SwiftUI

struct RootTabBackdrop: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    Group {
      if reduceTransparency {
        MemoraPalette.background
      } else {
        Rectangle()
          .fill(.regularMaterial)
          .overlay { MemoraPalette.background.opacity(0.45) }
      }
    }
    .mask {
      VStack(spacing: 0) {
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
          .frame(height: MemoraSpacing.lg)
        Color.black
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
