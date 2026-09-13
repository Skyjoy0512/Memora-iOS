import SwiftUI

/// Shared motion, so movement feels like one app and can be toned down for
/// Reduce Motion in a single place.
enum MemoraMotion {
  /// Whole screens and sheets changing.
  static let screen = Animation.smooth(duration: 0.38)
  /// Controls responding to a tap.
  static let control = Animation.snappy(duration: 0.26)
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
      .offset(y: hasAppeared || reduceMotion ? 0 : 16)
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
  @State private var isRevealed = false

  func body(content: Content) -> some View {
    content
      .opacity(isRevealed ? 1 : 0)
      .blur(radius: isRevealed || reduceMotion ? 0 : 5)
      .offset(y: isRevealed || reduceMotion ? 0 : 6)
      .onAppear {
        withAnimation(animation) {
          isRevealed = true
        }
      }
  }

  private var animation: Animation {
    reduceMotion
      ? .easeOut(duration: 0.18)
      : MemoraMotion.screen.delay(delay)
  }
}
