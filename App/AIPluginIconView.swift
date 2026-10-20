import SwiftUI

struct AIPluginIconView: View {
  var icon: AIPluginIcon
  var size: CGFloat = 20
  var body: some View {
    Group {
      if icon.kind == .asset, let name = icon.assetName, let image = UIImage(named: name) {
        Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
      } else {
        Image(icon: icon.kind == .asset ? icon.fallbackIcon : icon.systemSymbol).resizable().scaledToFit()
      }
    }
    .frame(width: size, height: size)
    .foregroundStyle(.primary)
    .accessibilityHidden(true)
  }
}
