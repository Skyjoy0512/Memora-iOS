import SwiftUI

struct ToolsCatalogRow: View {
  var title: String
  var summary: String
  var badge: String? = nil
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.xs + MemoraSpacing.xxs) {
      Text(title).font(.body.weight(.medium)).foregroundStyle(MemoraPalette.textPrimary)
      Text(summary)
        .font(.subheadline)
        .foregroundStyle(MemoraPalette.textSecondary)
        .lineSpacing(3)
        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        .fixedSize(horizontal: false, vertical: true)
      if let badge {
        Text(badge).font(.caption).foregroundStyle(MemoraPalette.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, MemoraSpacing.xs)
  }
}
