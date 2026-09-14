import SwiftUI

struct LifeLogRow: View {
  var entry: LifeLogEntry

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 46, alignment: .leading)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(entry.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Spacer(minLength: 8)
          Text(entry.source.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        Text(entry.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}
