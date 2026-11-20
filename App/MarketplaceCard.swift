import SwiftUI

struct MarketplaceCard: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var item: MarketplaceItem
  var featured = false
  var showsFullText = false
  var badge: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MarketplaceArtwork(item: item, featured: featured)
      VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
        if featured {
          Text("おすすめのスキル").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        cardText(Text(item.title).font(featured ? .title2.weight(.semibold) : .headline))
        cardText(Text(item.summary).font(.subheadline).foregroundStyle(.secondary))
        HStack {
          Text(badge ?? (featured ? "Memora" : item.category)).font(.caption).foregroundStyle(.secondary)
          Spacer(minLength: 8)
          if featured {
            Text("表示").font(.subheadline.weight(.semibold))
              .padding(.horizontal, MemoraSpacing.lg).padding(.vertical, MemoraSpacing.sm)
              .foregroundStyle(MemoraPalette.actionLabel)
              .background(MemoraPalette.action, in: Capsule())
          } else {
            Image(icon: .chevronRight, size: 12).accessibilityHidden(true)
          }
        }
        .padding(.top, MemoraSpacing.xs)
      }
      .padding(MemoraSpacing.card)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .background(MemoraPalette.card)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .contentShape(RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func cardText(_ text: Text) -> some View {
    if featured || showsFullText || typeSize.isAccessibilitySize {
      text.fixedSize(horizontal: false, vertical: true)
    } else {
      text.lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
    }
  }
}
