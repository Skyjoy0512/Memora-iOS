import SwiftUI

struct LifeLogRow: View {
  var entry: LifeLogEntry
  var connectsToNext = false
  @State private var photo: UIImage?

  var body: some View {
    JournalTimelineRow(time: entry.occurredAt.formatted(date: .omitted, time: .shortened),
      icon: entry.title == "起床" && entry.kind == .memo ? .sunrise : entry.meetingID == nil ? entry.kind.symbol : .waveform,
      tint: entry.title == "起床" && entry.kind == .memo ? .orange : .primary,
      railColor: entry.title == "起床" && entry.kind == .memo ? .orange : .indigo,
      connectsToNext: connectsToNext) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(timeLabel)
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
          Spacer()
          if SampleContent.isSample(lifeLogEntry: entry) {
            SampleTag()
          }
          if isAutomatic {
            AutomaticLogTag()
          }
          Text(entry.source.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }

        Text(entry.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)

        if !entry.summary.isEmpty {
          Text(JournalRecapWriter.excerpt(entry.summary))
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineSpacing(3)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let eventDate = entry.eventDate {
          Label(eventDate.formatted(date: .abbreviated, time: .shortened), icon: .calendar)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }

        if let locationName = entry.locationName, !locationName.isEmpty {
          Label(locationName, icon: .locationFill)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        if (entry.kind == .location || entry.kind == .event),
           let place = JournalPlace(name: entry.locationName ?? entry.title,
             latitude: entry.latitude, longitude: entry.longitude) {
          JournalMapPreview(place: place, date: entry.occurredAt)
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
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
  }

  /// A stay shows its whole span; anything else shows just its time.
  private var timeLabel: String {
    let start = entry.occurredAt.formatted(date: .omitted, time: .shortened)
    guard let endDate = entry.endDate else { return start }
    return "\(start)〜\(endDate.formatted(date: .omitted, time: .shortened))"
  }

  private var isAutomatic: Bool {
    entry.origin != .manual
  }

  /// The whole entry as one sentence, including that it has a photo.
  private var accessibilityLabel: String {
    var parts = [
      timeLabel,
      entry.source.label
    ]
    if SampleContent.isSample(lifeLogEntry: entry) {
      parts.append("サンプル")
    }
    parts.append(entry.title)
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
