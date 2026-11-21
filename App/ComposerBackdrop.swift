import SwiftUI

struct ComposerBackdrop: View {
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
      .frame(height: MemoraSpacing.group)
      // Bring in the blur just inside the footer so the list above stays sharp.
      .mask {
        VStack(spacing: 0) {
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
            .frame(height: MemoraSpacing.sm)
          Color.black
        }
      }
      MemoraPalette.background
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
