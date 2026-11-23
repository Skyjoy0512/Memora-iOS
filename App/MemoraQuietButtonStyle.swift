import SwiftUI

/// Quiet controls acknowledge a press without adding another surface.
struct MemoraQuietButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
      .animation(reduceMotion ? nil : MemoraMotion.press, value: configuration.isPressed)
  }
}
