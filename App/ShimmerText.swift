import SwiftUI

/// Text with a light passing across it while something is under way. Reduce
/// Motion keeps the text still.
struct ShimmerText: View {
  var text: String
  var isActive = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    if isActive && !reduceMotion && scenePhase == .active {
      TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
        let phase = context.date.timeIntervalSinceReferenceDate
          .truncatingRemainder(dividingBy: MemoraLoadingPolicy.shimmerSeconds)
          / MemoraLoadingPolicy.shimmerSeconds
        Text(text)
          .foregroundStyle(.secondary)
          .overlay {
            Text(text)
              .accessibilityHidden(true)
              .foregroundStyle(.primary)
              .mask {
                GeometryReader { proxy in
                  LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * 0.5)
                    .offset(x: (phase * 2 - 0.5) * proxy.size.width)
                }
              }
          }
      }
    } else {
      Text(text).foregroundStyle(.secondary)
    }
  }
}
