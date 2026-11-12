import SwiftUI

struct MarketplaceItemIcon: View {
  var item: MarketplaceItem
  var size: CGFloat = 48

  var body: some View {
    Group {
      if case .service = item {
        AIPluginIconView(icon: .resolve(pluginID: item.id, name: item.title), size: size * 0.7)
      } else {
        Image(icon: item.icon, size: size * 0.48)
          .foregroundStyle(MemoraPalette.textPrimary)
      }
    }
    .frame(width: size, height: size)
    .background(MemoraPalette.background, in: RoundedRectangle(cornerRadius: size * 0.24))
    .overlay {
      RoundedRectangle(cornerRadius: size * 0.24)
        .strokeBorder(MemoraPalette.border, lineWidth: 1)
    }
    .accessibilityHidden(true)
  }
}
