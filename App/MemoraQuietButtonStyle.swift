import SwiftUI

/// Quiet controls acknowledge a press without adding another surface.
struct MemoraQuietButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
      .animation(MemoraMotion.press, value: configuration.isPressed)
  }
}
