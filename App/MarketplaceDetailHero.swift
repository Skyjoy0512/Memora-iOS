import SwiftUI

struct MarketplaceDetailHero<Action: View>: View {
  var item: MarketplaceItem
  var subtitle: String
  @ViewBuilder var action: () -> Action

  var body: some View {
    VStack(spacing: MemoraSpacing.xl) {
      Group {
        if case .service = item {
          AIPluginIconView(icon: .resolve(pluginID: item.id, name: item.title), size: 56)
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
        } else {
          Image(icon: item.icon, size: 52)
            .foregroundStyle(.white)
            .padding(26)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 26))
        }
      }
      .accessibilityHidden(true)

      VStack(spacing: MemoraSpacing.sm) {
        Text(item.title).font(.title.weight(.semibold))
          .foregroundStyle(.white)
          .accessibilityAddTraits(.isHeader)
        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.9))
      }
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      action()
    }
    .padding(MemoraSpacing.xl)
    .padding(.vertical, MemoraSpacing.lg)
    .frame(maxWidth: .infinity)
    .background {
      LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom))
    }
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("marketplace.detail.hero")
  }
}
