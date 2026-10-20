import SwiftUI

/// Shared motion, so movement feels like one app and can be toned down for
/// Reduce Motion in a single place.
enum MemoraMotion {
  /// Whole screens and sheets changing.
  static let screen = Animation.smooth(duration: 0.32)
  static let drawer = Animation.smooth(duration: 0.3)
  /// Controls responding to a tap.
  static let control = Animation.snappy(duration: 0.22)
  static let press = Animation.smooth(duration: 0.14)
  /// Moments worth celebrating, such as finishing a recording.
  static let emphasis = Animation.bouncy(duration: 0.46, extraBounce: 0.08)
}

extension View {
  /// Fades and lifts a view into place on first appearance.
  func memoraAppear(delay: Double = 0) -> some View {
    modifier(MemoraAppear(delay: delay))
  }

  /// Lets important language resolve into place without turning reading into
  /// a visual effect. Reduce Motion keeps only the brief opacity change.
  func memoraTextReveal(delay: Double = 0) -> some View {
    modifier(MemoraTextReveal(delay: delay))
  }
}

private struct MemoraAppear: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var delay: Double
  @State private var hasAppeared = false

  func body(content: Content) -> some View {
    content
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: hasAppeared || reduceMotion ? 0 : 8)
      .onAppear {
        withAnimation(animation) {
          hasAppeared = true
        }
      }
  }

  private var animation: Animation {
    reduceMotion
      ? .easeOut(duration: 0.2)
      : MemoraMotion.screen.delay(delay)
  }
}

private struct MemoraTextReveal: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var delay: Double
  @State private var revealProgress: Double = 0
  @State private var isShown = false

  func body(content: Content) -> some View {
    content
      .textRenderer(TextRevealRenderer(progress: revealProgress))
      // Symbols and shapes beside the text do not go through the renderer, so
      // they fade in quickly on their own instead of popping in.
      .opacity(isShown ? 1 : 0)
      .onAppear {
        guard revealProgress < 1 else { return }
        if reduceMotion {
          // Only the brief fade; the text itself is drawn complete.
          revealProgress = 1
          withAnimation(.easeOut(duration: 0.18)) {
            isShown = true
          }
        } else {
          withAnimation(.easeOut(duration: 0.24).delay(delay)) {
            isShown = true
          }
          withAnimation(.linear(duration: 0.75).delay(delay)) {
            revealProgress = 1
          }
        }
      }
  }
}
