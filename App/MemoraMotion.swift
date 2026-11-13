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
  /// a visual effect. Reduce Motion shows the complete text immediately.
  func memoraTextReveal(enabled: Bool = true, delay: Double = 0) -> some View {
    modifier(MemoraTextReveal(enabled: enabled, delay: delay))
  }
}

private struct MemoraAppear: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var delay: Double
  @State private var hasAppeared = false

  func body(content: Content) -> some View {
    content
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: hasAppeared || reduceMotion ? 0 : 4)
      .onAppear {
        withAnimation(animation) {
          hasAppeared = true
        }
      }
  }

  private var animation: Animation {
    reduceMotion
      ? .smooth(duration: 0.16)
      : MemoraMotion.screen.delay(delay)
  }
}

private struct MemoraTextReveal: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var enabled: Bool
  var delay: Double
  @State private var revealProgress: Double
  @State private var isShown: Bool

  init(enabled: Bool, delay: Double) {
    self.enabled = enabled
    self.delay = delay
    _revealProgress = State(initialValue: enabled ? 0 : 1)
    _isShown = State(initialValue: !enabled)
  }

  func body(content: Content) -> some View {
    content
      .textRenderer(TextRevealRenderer(progress: revealProgress))
      // Symbols and shapes beside the text do not go through the renderer, so
      // they fade in quickly on their own instead of popping in.
      .opacity(isShown ? 1 : 0)
      .onAppear {
        guard revealProgress < 1 else { return }
        if reduceMotion || !enabled {
          revealProgress = 1
          isShown = true
        } else {
          withAnimation(.easeOut(duration: 0.24).delay(delay)) {
            isShown = true
          }
          withAnimation(.smooth(duration: 0.32).delay(delay)) {
            revealProgress = 1
          }
        }
      }
      .onChange(of: reduceMotion) { _, reduced in
        if reduced { revealProgress = 1; isShown = true }
      }
  }
}
