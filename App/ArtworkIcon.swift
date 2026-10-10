import SwiftUI

struct ArtworkIcon: View {
  var artwork: MemoraArtwork
  var size: CGFloat

  var body: some View {
    Image(artwork.rawValue)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
