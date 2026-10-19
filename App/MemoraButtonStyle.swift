import SwiftUI

/// Content actions use solid or quiet surfaces; floating chrome keeps native glass.
struct MemoraButtonStyle: ButtonStyle {
  enum Emphasis { case primary, secondary }
  var emphasis: Emphasis = .primary
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(MemoraTypography.body.weight(.medium))
      .multilineTextAlignment(.center)
      .padding(.horizontal, MemoraSpacing.xl)
      .padding(.vertical, MemoraSpacing.md)
      .frame(minHeight: MemoraSpacing.touchTarget)
      .foregroundStyle(emphasis == .primary ? MemoraPalette.actionLabel : MemoraPalette.textPrimary)
      .background(emphasis == .primary ? MemoraPalette.action : MemoraPalette.selection, in: Capsule())
      .contentShape(Capsule())
      .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.72 : 1)
  }
}
