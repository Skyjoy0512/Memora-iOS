import SwiftUI

struct SettingsIcon: View {
  var icon: MemoraIcon
  var color: Color
  /// Shrinks a glyph that reads heavier than its neighbours (three people,
  /// say), so every tile looks the same weight.
  var glyphScale: CGFloat = 1
  var artwork: MemoraArtwork? = nil
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29
  @ScaledMetric(relativeTo: .body) private var monochromeSize: CGFloat = 22
  @Environment(\.settingsIconStyle) private var style

  var body: some View {
    if style == .monochrome {
      let glyphSize = monochromeSize * glyphScale
      glyph(size: glyphSize)
        .font(.system(size: glyphSize, weight: .regular))
        .foregroundStyle(.primary)
        .frame(width: monochromeSize, height: monochromeSize)
        .accessibilityHidden(true)
    } else {
      let glyphSize = size * 0.58 * glyphScale
      glyph(size: glyphSize)
        .font(.system(size: glyphSize, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
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
