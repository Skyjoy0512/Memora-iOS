import SwiftUI

struct ProjectDocumentRow: View {
  var document: MemoraDocument

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(icon: document.kind.symbol, size: 17)
        .frame(width: ProjectLayout.iconSide, height: 24)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(document.displayTitle)
          .font(MemoraTypography.body.weight(.medium))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(document.kind.label) · \(MemoraFormat.relativeDate(document.updatedAt))")
          .font(MemoraTypography.metadata).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: ProjectLayout.minimumRowHeight, alignment: .center)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
