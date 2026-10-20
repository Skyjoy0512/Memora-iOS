import SwiftUI

/// Keep the spoken action even when a toolbar only displays its icon.
struct ToolbarIconButton: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  var action: () -> Void
  @Environment(\.memoraToolbarControlSize) private var controlSize

  init(_ title: LocalizedStringKey, icon: MemoraIcon, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.action = action
  }

  var body: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      ToolbarIconGlyph(icon: icon)
        .frame(width: controlSize, height: controlSize)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(title)
  }
}
