import SwiftUI

struct MemoraMenuButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed ? MemoraPalette.selection : .clear,
        in: RoundedRectangle(cornerRadius: MemoraRadius.small))
  }
}
