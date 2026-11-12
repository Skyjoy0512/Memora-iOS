import SwiftUI

struct MarketplaceDetailActionLabel: View {
  var title: String
  var icon: MemoraIcon?

  var body: some View {
    HStack(spacing: MemoraSpacing.sm) {
      if let icon { Image(icon: icon, size: 20).accessibilityHidden(true) }
      Text(title)
        .font(.body.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(MemoraPalette.actionLabel)
    .padding(.horizontal, MemoraSpacing.xxl)
    .padding(.vertical, MemoraSpacing.lg)
    .frame(maxWidth: .infinity, minHeight: 52)
    .background(MemoraPalette.action, in: Capsule())
    .contentShape(Capsule())
  }
}
