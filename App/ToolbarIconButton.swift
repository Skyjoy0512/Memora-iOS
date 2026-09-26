import SwiftUI

/// Keep the spoken action even when a toolbar only displays its icon.
struct ToolbarIconButton: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  var action: () -> Void
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 21

  init(_ title: LocalizedStringKey, icon: MemoraIcon, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Image(icon: icon)
        .resizable()
        .scaledToFit()
        .frame(width: iconSize, height: iconSize)
        .frame(minWidth: 32, minHeight: 32)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(title)
  }
}
