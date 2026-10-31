import SwiftUI

struct MarketplaceShelf: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var cardWidth = 218
  var section: ToolsSection
  var items: [MarketplaceItem]

  var body: some View {
    let headingLayout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: MemoraSpacing.sm))
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      headingLayout {
        Text(section.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        NavigationLink { MarketplaceCatalogView(section: section) } label: {
          Text("すべて見る").font(.subheadline).frame(minHeight: 44)
        }
        .accessibilityLabel("\(section.title)をすべて見る")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, MemoraSpacing.screen)
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: MemoraSpacing.md) {
          ForEach(items) { item in
            NavigationLink { item.destination } label: { MarketplaceCard(item: item) }
              .buttonStyle(.plain)
              .frame(width: min(cardWidth, 320))
              .accessibilityIdentifier("marketplace.item.\(item.id)")
          }
        }
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.bottom, 2)
      }
      .scrollIndicators(.hidden)
    }
  }
}
