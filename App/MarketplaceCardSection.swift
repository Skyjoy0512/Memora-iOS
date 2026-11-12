import SwiftUI

struct MarketplaceCardSection: View {
  var title: String
  var items: [MarketplaceItem]
  var badges: [String: String] = [:]
  var onConnectorDismiss: (() -> Void)?

  var body: some View {
    Section {
      ForEach(items) { item in
        MarketplaceListRow(item: item, badge: badges[item.id], onConnectorDismiss: onConnectorDismiss)
          .accessibilityIdentifier("marketplace.catalog.\(item.id)")
      }
    } header: {
      Text(title)
        .font(.headline)
        .foregroundStyle(MemoraPalette.textSecondary)
        .padding(.top, MemoraSpacing.xl)
        .padding(.bottom, MemoraSpacing.sm)
        .accessibilityAddTraits(.isHeader)
    }
  }
}
