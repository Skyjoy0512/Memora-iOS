import SwiftUI

struct SettingsLabel: View {
  var title: String
  var icon: MemoraIcon
  var color: Color
  var glyphScale: CGFloat
  var artwork: MemoraArtwork?

  init(_ title: String, icon: MemoraIcon, color: Color, glyphScale: CGFloat = 1, artwork: MemoraArtwork? = nil) {
    self.title = title
    self.icon = icon
    self.color = color
    self.glyphScale = glyphScale
    self.artwork = artwork
  }

  var body: some View {
    HStack(spacing: 12) {
      SettingsIcon(icon: icon, color: color, glyphScale: glyphScale, artwork: artwork)
      Text(title)
    }
  }
}
