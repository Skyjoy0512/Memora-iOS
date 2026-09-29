import SwiftUI

/// One coming calendar event in the Files screen's row: a date tile, when it
/// starts, and its title.
struct UpcomingEventCard: View {
  var meeting: UpcomingMeeting

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
    .memoraCard(radius: 22)
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  private var dateTile: some View {
    VStack(spacing: 0) {
      Text(meeting.start, format: .dateTime.weekday(.abbreviated))
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(.tint)
      Text(meeting.start, format: .dateTime.day())
        .font(.title2.weight(.semibold).monospacedDigit())
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 52, height: 56)
    .background(Color(uiColor: .systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityHidden(true)
  }
}
