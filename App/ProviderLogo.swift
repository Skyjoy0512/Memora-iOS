import SwiftUI

/// Keep provider artwork in its original colors on a neutral plate in both appearances.
struct ProviderLogo: View {
  var provider: LLMProvider
  var size: CGFloat = 30

  var body: some View {
    Image(provider.logoAssetName)
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .padding(size * 0.2)
      .frame(width: size, height: size)
      .background(
        Color.white,
        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
      }
      .accessibilityHidden(true)
  }
}
