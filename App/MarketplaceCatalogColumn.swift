import SwiftUI

struct MarketplaceCatalogColumn<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MemoraSpacing.md, content: content)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.bottom, MemoraSpacing.section)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier("marketplace.catalog.column")
  }
}
