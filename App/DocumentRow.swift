import SwiftUI

/// One document in a list: its kind, title, and where and when it was made.
struct DocumentRow: View {
  var document: MemoraDocument
  var spaceName: String?

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let preview = document.preview
    HStack(spacing: 14) {
      MemoraInterfaceIcon(icon: document.kind.symbol)

      VStack(alignment: .leading, spacing: 3) {
        Text(document.displayTitle)
          .font(.body.weight(.medium))
          .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        if document.kind == .document && !preview.isEmpty {
          Text(preview)
            .font(MemoraTypography.secondary)
            .foregroundStyle(MemoraPalette.textSecondary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
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
    var parts = [document.weekStart == nil ? document.kind.label : "週報", MemoraFormat.documentDate(document.createdAt)]
    if let spaceName {
      parts.append(spaceName)
    }
    if document.kind == .slides {
      parts.append("\(document.slides.count)枚")
    }
    return parts.joined(separator: " · ")
  }
}
