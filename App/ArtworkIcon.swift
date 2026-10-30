import SwiftUI

struct ArtworkIcon: View {
  var artwork: MemoraArtwork
  var size: CGFloat

  var body: some View {
    Image(icon: artwork.icon, size: size)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
