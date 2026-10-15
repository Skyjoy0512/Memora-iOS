import SwiftUI

/// Text with a light passing across it while something is under way. Reduce
/// Motion keeps the text still.
struct ShimmerText: View {
  var text: String
  @State private var phase: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Text(text)
      .foregroundStyle(.tertiary)
      .overlay {
        if !reduceMotion {
          Text(text)
            .foregroundStyle(.primary)
            .mask {
              GeometryReader { proxy in
                LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                  .frame(width: proxy.size.width * 0.5)
                  .offset(x: (phase * 2 - 0.5) * proxy.size.width)
              }
            }
        }
      }
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: MemoraLoadingPolicy.shimmerSeconds).repeatForever(autoreverses: false)) {
          phase = 1
        }
      }
  }
}
