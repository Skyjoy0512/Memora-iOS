import SwiftUI

/// One document in a list: its kind, title, and where and when it was made.
struct DocumentRow: View {
  var document: MemoraDocument
  var spaceName: String?

  var body: some View {
    HStack(spacing: 14) {
      MemoraInterfaceIcon(icon: document.kind.symbol)

      VStack(alignment: .leading, spacing: 3) {
        Text(document.displayTitle)
          .font(.body.weight(.semibold))
          .lineLimit(2)
        Text(caption)
          .font(MemoraTypography.metadata)
          .foregroundStyle(MemoraPalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, MemoraSpacing.xs)
    .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var caption: String {
    var parts = [document.weekStart == nil ? document.kind.label : "週報", document.createdAt.formatted(date: .abbreviated, time: .omitted)]
    if let spaceName {
      parts.append(spaceName)
    }
    if document.kind == .slides {
      parts.append("\(document.slides.count)枚")
    }
    return parts.joined(separator: " · ")
  }
}
