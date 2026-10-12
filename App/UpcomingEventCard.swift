import SwiftUI

/// One coming calendar event in the Files screen's row: a date tile, when it
/// starts, and its title.
struct UpcomingEventCard: View {
  var meeting: UpcomingMeeting
  @ScaledMetric(relativeTo: .title2) private var dateTileWidth = 52.0
  @ScaledMetric(relativeTo: .title2) private var dateTileHeight = 56.0

  var body: some View {
    HStack(spacing: 14) {
      dateTile

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(meeting.start, format: .dateTime.month().day().weekday().hour().minute())
            .font(.subheadline)
            .foregroundStyle(.secondary)
          if meeting.isOnline {
            Label("Web会議", icon: .video)
              .labelStyle(.iconOnly)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }
        Text(meeting.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(2)
      }

      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    .memoraCard(radius: 22, fill: Color(uiColor: .secondarySystemGroupedBackground))
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  private var dateTile: some View {
    VStack(spacing: 2) {
      Text(meeting.start, format: .dateTime.weekday(.abbreviated))
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
      Text(meeting.start, format: .dateTime.day())
        .font(.title2.weight(.semibold).monospacedDigit())
        .foregroundStyle(.primary)
    }
    .padding(.vertical, 6)
    .frame(width: dateTileWidth)
    .frame(minHeight: dateTileHeight)
    .background(Color(uiColor: .systemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityHidden(true)
  }
}
