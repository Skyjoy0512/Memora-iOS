import SwiftUI

struct MarketplaceDetailActionLabel: View {
  var title: String
  var icon: MemoraIcon = .arrowUpRight

  var body: some View {
    HStack(spacing: MemoraSpacing.md) {
      Text(title).font(.body.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      Image(icon: icon, size: 20)
        .frame(width: 40, height: 40)
        .background(.white.opacity(0.1), in: Circle())
        .accessibilityHidden(true)
    }
    .foregroundStyle(.white)
    .padding(MemoraSpacing.lg)
    .frame(maxWidth: .infinity, minHeight: 60)
    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
    .contentShape(RoundedRectangle(cornerRadius: 12))
  }
}
