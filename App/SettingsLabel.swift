import SwiftUI

/// A settings row title with its colored icon.
struct SettingsLabel: View {
  var title: String
  var icon: MemoraIcon
  var color: Color

  init(_ title: String, icon: MemoraIcon, color: Color) {
    self.title = title
    self.icon = icon
    self.color = color
  }

  var body: some View {
    Label {
      Text(title)
    } icon: {
      SettingsIcon(icon: icon, color: color)
    }
  }
}
