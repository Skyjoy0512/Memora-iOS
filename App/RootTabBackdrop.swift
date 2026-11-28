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
        // A longer fade so content softens before it reaches the tab row.
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
          .frame(height: MemoraSpacing.group)
        Color.black
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
