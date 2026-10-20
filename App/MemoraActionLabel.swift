import SwiftUI

/// The whole label belongs inside its Button, including padding and hit area.
struct MemoraActionLabel: View {
  var title: String
  var detail: String? = nil
  var icon: MemoraIcon

  var body: some View {
    HStack(alignment: detail == nil ? .center : .top, spacing: MemoraSpacing.md) {
      MemoraInterfaceIcon(icon: icon)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(title).font(MemoraTypography.body.weight(.medium))
          .foregroundStyle(MemoraPalette.textPrimary)
        if let detail {
          Text(detail).font(MemoraTypography.metadata)
            .foregroundStyle(MemoraPalette.textSecondary)
            .lineSpacing(MemoraSpacing.xxs)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
    .padding(.horizontal, MemoraSpacing.sm)
    .padding(.vertical, detail == nil ? 0 : MemoraSpacing.sm)
    .contentShape(Rectangle())
  }
}
