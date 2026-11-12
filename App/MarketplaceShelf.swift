import SwiftUI

struct MarketplaceShelf: View {
  var section: ToolsSection
  var items: [MarketplaceItem]
  var onConnectorDismiss: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      NavigationLink { MarketplaceCatalogView(section: section) } label: {
        HStack(spacing: MemoraSpacing.sm) {
          Text(section.title).font(.headline)
          Image(icon: .chevronRight, size: 12).accessibilityHidden(true)
        }
        .foregroundStyle(MemoraPalette.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      }
      .accessibilityLabel("\(section.title)をすべて見る")
      .accessibilityAddTraits(.isHeader)
      ForEach(items) { item in
        MarketplaceListRow(item: item, onConnectorDismiss: onConnectorDismiss)
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, MemoraSpacing.screen)
  }
}
