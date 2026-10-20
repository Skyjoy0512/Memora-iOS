import SwiftUI

struct MemoraSectionHeading: View {
  var title: String
  var detail: String? = nil
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.md))
    layout {
      Text(title)
        .font(MemoraTypography.body.weight(.semibold))
        .foregroundStyle(MemoraPalette.textPrimary)
      if let detail {
        if !typeSize.isAccessibilitySize { Spacer(minLength: MemoraSpacing.sm) }
        Text(detail)
          .font(MemoraTypography.metadata)
          .foregroundStyle(MemoraPalette.textSecondary)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}
