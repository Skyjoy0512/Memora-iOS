import SwiftUI

/// One document in a list: its kind, title, and where and when it was made.
struct DocumentRow: View {
  var document: MemoraDocument
  var spaceName: String?

  var body: some View {
    HStack(spacing: 14) {
      Image(icon: document.kind.symbol)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 40, height: 40)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(document.displayTitle)
          .font(.body.weight(.semibold))
          .lineLimit(2)
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var caption: String {
    var parts = [document.kind.label, document.createdAt.formatted(date: .abbreviated, time: .omitted)]
    if let spaceName {
      parts.append(spaceName)
    }
    if document.kind == .slides {
      parts.append("\(document.slides.count)枚")
    }
    return parts.joined(separator: " · ")
  }
}
