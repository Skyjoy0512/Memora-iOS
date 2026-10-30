import SwiftUI

struct AIPluginIconView: View {
  var icon: AIPluginIcon
  var size: CGFloat = 20
  var body: some View {
    Image(icon: icon.icon, size: size)
    .frame(width: size, height: size)
    .foregroundStyle(.primary)
    .accessibilityHidden(true)
  }
}
