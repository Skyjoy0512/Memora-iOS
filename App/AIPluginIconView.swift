import SwiftUI

struct AIPluginIconView: View {
  var icon: AIPluginIcon
  var size: CGFloat = 20
  var body: some View {
    Group {
      if let asset = icon.brandAssetName {
        Image(asset).renderingMode(.original).resizable().scaledToFit()
      } else {
        Image(icon: icon.icon, size: size).foregroundStyle(.primary)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
