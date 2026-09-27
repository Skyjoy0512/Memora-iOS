import SwiftUI

/// A settings row title with its colored icon.
struct SettingsLabel: View {
  var title: String
  var icon: MemoraIcon
  var color: Color
  var glyphScale: CGFloat

  init(_ title: String, icon: MemoraIcon, color: Color, glyphScale: CGFloat = 1) {
    self.title = title
    self.icon = icon
    self.color = color
    self.glyphScale = glyphScale
  }

  var body: some View {
    HStack(spacing: 12) {
      SettingsIcon(icon: icon, color: color, glyphScale: glyphScale)
      Text(title)
    }
  }
}
