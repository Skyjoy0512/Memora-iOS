import SwiftUI

/// Keep the spoken action even when a toolbar only displays its icon.
struct ToolbarIconButton: View {
  var title: LocalizedStringKey
  var icon: MemoraIcon
  var action: () -> Void

  init(_ title: LocalizedStringKey, icon: MemoraIcon, action: @escaping () -> Void) {
    self.title = title
    self.icon = icon
    self.action = action
  }

  var body: some View {
    Button(title, icon: icon, action: action)
      .labelStyle(.iconOnly)
  }
}
