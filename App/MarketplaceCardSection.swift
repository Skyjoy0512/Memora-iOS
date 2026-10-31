import SwiftUI

struct MarketplaceCardSection: View {
  var title: String
  var items: [MarketplaceItem]
  var badges: [String: String] = [:]
  var onConnectorDismiss: (() -> Void)?

  var body: some View {
    Section {
      ForEach(items) { item in
        MarketplaceItemLink(item: item, onConnectorDismiss: onConnectorDismiss) {
          MarketplaceCard(item: item, showsFullText: true, badge: badges[item.id])
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("marketplace.catalog.\(item.id)")
      }
    } header: {
      HStack(alignment: .firstTextBaseline, spacing: MemoraSpacing.sm) {
        ToolsSectionHeading(title: title)
        Text(items.count.formatted()).font(.subheadline).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
    }
  }
}
