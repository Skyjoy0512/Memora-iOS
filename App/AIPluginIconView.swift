import SwiftUI

struct AIPluginIconView: View {
  var icon: AIPluginIcon
  var body: some View {
    Group {
      if icon.kind == .asset, let name = icon.assetName, let image = UIImage(named: name) {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
        Image(icon: icon.kind == .asset ? icon.fallbackIcon : icon.systemSymbol).resizable().scaledToFit()
      }
    }
    .frame(width: 20, height: 20)
    .foregroundStyle(.primary)
    .accessibilityHidden(true)
  }
}
