import SwiftUI

/// The label owns the touch area, not just the space around its glyph.
struct MemoraIconButton: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  var action: () -> Void

  init(_ title: LocalizedStringKey, icon: MemoraIcon, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Image(icon: icon, size: MemoraIconMetrics.glyph)
        .foregroundStyle(MemoraPalette.textPrimary)
        .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(MemoraQuietButtonStyle())
    .accessibilityLabel(title)
  }
}
