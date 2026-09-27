import SwiftUI

/// Keep the spoken action even when a toolbar only displays its icon.
struct ToolbarIconButton: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  var action: () -> Void
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

  init(_ title: LocalizedStringKey, icon: MemoraIcon, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Image(icon: icon)
        .font(.system(size: iconSize))
        .frame(minWidth: 36, minHeight: 36)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(title)
  }
}
