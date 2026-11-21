import SwiftUI

struct RootTabBackdrop: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if reduceTransparency {
          MemoraPalette.background
        } else {
          Rectangle()
            .fill(.regularMaterial)
            .overlay {
              LinearGradient(colors: [.clear, MemoraPalette.background], startPoint: .top, endPoint: .bottom)
            }
        }
      }
      .mask {
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
      }
      .frame(height: MemoraSpacing.lg)
      MemoraPalette.background
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
