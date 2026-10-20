import SwiftUI

struct ToolsCatalogRow: View {
  var title: String
  var summary: String
  var badge: String? = nil
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Text(title).font(.body).foregroundStyle(MemoraPalette.textPrimary)
      Text(summary)
        .font(.subheadline)
        .foregroundStyle(MemoraPalette.textSecondary)
        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
      if let badge {
        Text(badge).font(.caption).foregroundStyle(MemoraPalette.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, MemoraSpacing.xs)
  }
}
