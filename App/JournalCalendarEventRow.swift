import SwiftUI

/// One calendar event in the journal's day timeline. A recording tied to the
/// event opens the record; other events open their own detail.
struct JournalCalendarEventRow: View {
  /// The day being shown, so an event that began the night before reads as a
  /// continuation.
  var day: Date
  var event: JournalCalendarEvent
  var onOpen: (JournalCalendarEvent) -> Void
  @ScaledMetric(relativeTo: .caption) private var timeWidth: CGFloat = 46

  var body: some View {
    Group {
      if let meetingID = event.meetingID {
        NavigationLink(value: LibraryRoute.meeting(meetingID)) {
          label
        }
        .buttonStyle(.plain)
      } else {
        Button {
          onOpen(event)
        } label: {
          label
        }
        .buttonStyle(.plain)
        .accessibilityHint("予定の詳細を開きます")
      }
    }
  }

  private var label: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(timeText)
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: timeWidth, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(.headline)
        HStack(spacing: 4) {
          if let color = event.calendarColor {
            Circle()
              .fill(color)
              .frame(width: 8, height: 8)
          }
          Text(event.calendarTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .padding(.vertical, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(timeText)、予定、\(event.title)、\(event.calendarTitle)")
  }

  private var timeText: String {
    let dayStart = Calendar.current.startOfDay(for: day)
    let end = event.end.formatted(date: .omitted, time: .shortened)
    if event.start < dayStart {
      return "〜\(end)"
    }
    return "\(event.start.formatted(date: .omitted, time: .shortened))〜\(end)"
  }
}
