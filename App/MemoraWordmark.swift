import SwiftUI

/// Appearance variants retain the supplied geometry and colors without tinting.
struct MemoraWordmark: View {
  var width: CGFloat = 118

  var body: some View {
    Image("memora-wordmark")
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .frame(width: width, height: width * 68 / 410)
      .accessibilityLabel("Memora")
  }
}
