import SwiftUI

struct LifeLogRow: View {
  var entry: LifeLogEntry
  @State private var photo: UIImage?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 6) {
        ZStack {
          Circle()
            .fill(Color(uiColor: .secondarySystemBackground))
          Image(systemName: entry.kind.symbol)
            .font(.caption.weight(.semibold))
        }
        .frame(width: 34, height: 34)

        Rectangle()
          .fill(Color(uiColor: .separator).opacity(0.45))
          .frame(width: 1)
          .frame(maxHeight: .infinity)
      }

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
          Spacer()
          Text(entry.source.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }

        Text(entry.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)

        if !entry.summary.isEmpty {
          Text(entry.summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let eventDate = entry.eventDate {
          Label(eventDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }

        if let locationName = entry.locationName, !locationName.isEmpty {
          Label(locationName, systemImage: "location.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }

        if let name = entry.photoFileName {
          Group {
            if let photo {
              Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .accessibilityLabel("添付写真")
            } else {
              // A quiet placeholder while the small copy is decoded.
              Color.primary.opacity(0.05)
                .accessibilityHidden(true)
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 172)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .task(id: name) {
            photo = await MediaImageCache.image(named: name, maxPixelSize: 600)
          }
        }
      }
      .padding(16)
      .memoraCard(radius: 20)
      .padding(.bottom, 8)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  /// The whole entry as one sentence, including that it has a photo.
  private var accessibilityLabel: String {
    var parts = [
      entry.createdAt.formatted(date: .omitted, time: .shortened),
      entry.source.label,
      entry.title
    ]
    if !entry.summary.isEmpty {
      parts.append(entry.summary)
    }
    if let eventDate = entry.eventDate {
      parts.append("予定 \(eventDate.formatted(date: .abbreviated, time: .shortened))")
    }
    if let locationName = entry.locationName, !locationName.isEmpty {
      parts.append(locationName)
    }
    if entry.photoFileName != nil {
      parts.append("添付写真あり")
    }
    return parts.joined(separator: "、")
  }
}
