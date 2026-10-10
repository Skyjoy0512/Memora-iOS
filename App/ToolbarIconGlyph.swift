import SwiftUI

struct ToolbarIconGlyph: View {
  var icon: MemoraIcon
  var artwork: MemoraArtwork?
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
  @ScaledMetric(relativeTo: .body) private var searchIconSize: CGFloat = 26

  var body: some View {
    Group {
      if icon == .magnifyingglass {
        ArtworkIcon(artwork: .searchIntelligence, size: min(searchIconSize, 32))
      } else if let artwork {
        ArtworkIcon(artwork: artwork, size: min(iconSize, 32))
      } else {
        Image(icon: icon, size: min(iconSize, 32))
          .font(.system(size: min(iconSize, 32)))
      }
    }
    .foregroundStyle(.primary)
    .accessibilityHidden(true)
  }
}
