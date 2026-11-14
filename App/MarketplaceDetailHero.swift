import SwiftUI

struct MarketplaceDetailHero<Action: View>: View {
  var item: MarketplaceItem
  var subtitle: String
  @ViewBuilder var action: () -> Action

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
      MarketplaceItemIcon(item: item, size: 56)
      VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
        Text(item.title)
          .font(MemoraTypography.screenTitle)
          .foregroundStyle(MemoraPalette.textPrimary)
          .accessibilityAddTraits(.isHeader)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(MemoraPalette.textSecondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      action()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("marketplace.detail.hero")
  }
}
