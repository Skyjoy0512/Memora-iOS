import SwiftUI

/// One coming calendar event in the Files screen's row, drawn the way the
/// Calendar app marks an event: a bar in the calendar's colour beside when it
/// is and what it is.
struct UpcomingEventCard: View {
  var meeting: UpcomingMeeting

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Capsule()
        .fill(accent)
        .frame(width: 4)

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text(UpcomingMeetingFormat.day(meeting.start))
            .foregroundStyle(accent)
          Text(UpcomingMeetingFormat.timeRange(meeting))
            .foregroundStyle(.secondary)
            .monospacedDigit()
          if meeting.isOnline {
            Spacer(minLength: 4)
            Label("Web会議", icon: .video)
              .labelStyle(.iconOnly)
              .foregroundStyle(.secondary)
          }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)

        Text(meeting.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }

      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
    .memoraCard(radius: 22)
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var accent: Color {
    meeting.calendarColor ?? .accentColor
  }
}
