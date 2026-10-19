import SwiftUI

struct SettingsLabel: View {
  var title: String
  var icon: MemoraIcon
  var glyphScale: CGFloat
  var artwork: MemoraArtwork?

  init(_ title: String, icon: MemoraIcon, glyphScale: CGFloat = 1, artwork: MemoraArtwork? = nil) {
    self.title = title
    self.icon = icon
    self.glyphScale = glyphScale
    self.artwork = artwork
  }

  var body: some View {
    HStack(spacing: MemoraSpacing.md) {
      SettingsIcon(icon: icon, glyphScale: glyphScale, artwork: artwork)
      Text(title)
    }
  }
}
