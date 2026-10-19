import SwiftUI

struct SettingsIcon: View {
  var icon: MemoraIcon
  /// Shrinks a glyph that reads heavier than its neighbours (three people,
  /// say), so every tile looks the same weight.
  var glyphScale: CGFloat = 1
  var artwork: MemoraArtwork? = nil
  @ScaledMetric(relativeTo: .body) private var monochromeSize: CGFloat = 22

  var body: some View {
      let glyphSize = monochromeSize * glyphScale
      glyph(size: glyphSize)
        .font(.system(size: glyphSize, weight: .regular))
        .foregroundStyle(.primary)
        .frame(width: monochromeSize, height: monochromeSize)
        .accessibilityHidden(true)
  }

  @ViewBuilder
  private func glyph(size: CGFloat) -> some View {
    if let artwork {
      ArtworkIcon(artwork: artwork, size: size)
    } else {
      Image(icon: icon, size: size)
    }
  }
}
