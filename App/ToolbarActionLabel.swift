import SwiftUI

struct ToolbarActionLabel: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  @Environment(\.memoraToolbarControlSize) private var controlSize

  init(_ title: LocalizedStringKey, icon: MemoraIcon) {
    self.title = title
    self.icon = icon
  }

  var body: some View {
    Label {
      Text(title)
    } icon: {
      ToolbarIconGlyph(icon: icon)
    }
    .labelStyle(.iconOnly)
    .frame(width: controlSize, height: controlSize)
    .contentShape(Rectangle())
    .accessibilityLabel(title)
  }
}
