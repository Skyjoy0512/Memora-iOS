import SwiftUI

struct ProjectSourceRow: View {
  var source: ProjectSource

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(icon: source.icon)
        .font(.body).foregroundStyle(.secondary)
        .frame(width: ProjectLayout.iconSide, height: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(source.title).font(.body.weight(.semibold)).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(source.kindLabel) · \(source.createdAt.formatted(date: .abbreviated, time: .omitted))")
          .font(.footnote).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(source.statusLabel).font(.footnote).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
