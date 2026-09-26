import SwiftUI

/// A provider's mark on a small tile, so every logo sits on the same shape and
/// the one-color marks follow light and dark appearance.
struct ProviderLogo: View {
  var provider: LLMProvider
  var size: CGFloat = 30

  var body: some View {
    Image(provider.logoAssetName)
      .resizable()
      .scaledToFit()
      .foregroundStyle(.primary)
      .padding(size * 0.2)
      .frame(width: size, height: size)
      .background(
        Color(uiColor: .systemBackground),
        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
      }
      .accessibilityHidden(true)
  }
}
