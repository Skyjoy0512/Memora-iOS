import SwiftUI

struct ComposerBackdrop: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    let edgeHeight = MemoraSpacing.xl
    MemoraPalette.background
      .overlay(alignment: .top) {
        Group {
          if reduceTransparency {
            MemoraPalette.background
          } else {
            Rectangle()
              .fill(.thinMaterial)
              .overlay {
                LinearGradient(colors: [.clear, MemoraPalette.background], startPoint: .top, endPoint: .bottom)
              }
          }
        }
        .mask {
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: edgeHeight)
        .offset(y: -edgeHeight)
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
