import SwiftUI

struct MarketplaceArtwork: View {
  var item: MarketplaceItem
  var featured = false

  var body: some View {
    ZStack {
      LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(.white.opacity(0.07))
        .frame(width: featured ? 260 : 160, height: featured ? 260 : 160)
        .offset(x: featured ? 130 : 80, y: 60)
      if case .service = item {
        AIPluginIconView(icon: .resolve(pluginID: item.id, name: item.title), size: featured ? 64 : 38)
          .padding(featured ? 24 : 16)
          .background(MemoraPalette.elevated, in: RoundedRectangle(cornerRadius: featured ? 26 : 18))
      } else {
        Image(icon: item.icon, size: featured ? 64 : 38)
          .foregroundStyle(.white)
          .padding(featured ? 24 : 16)
          .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: featured ? 26 : 18))
          .rotationEffect(.degrees(-8))
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: featured ? 190 : 112)
    .clipped()
    .accessibilityHidden(true)
  }
}
