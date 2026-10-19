import SwiftUI

struct ProjectSourceRow: View {
  var source: ProjectSource

  var body: some View {
    HStack(alignment: .top, spacing: MemoraSpacing.md) {
      ProjectSourceThumbnail(source: source)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(source.title).font(MemoraTypography.body.weight(.medium)).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(source.kindLabel) · \(MemoraFormat.relativeDate(source.createdAt))")
          .font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(source.statusLabel).font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
