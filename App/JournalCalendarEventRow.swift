import SwiftUI

/// One calendar event in the journal's day timeline. A recording tied to the
/// event opens the record; other events open their own detail.
struct JournalCalendarEventRow: View {
  /// The day being shown, so an event that began the night before reads as a
  /// continuation.
  var day: Date
  var event: JournalCalendarEvent
  var onOpen: (JournalCalendarEvent) -> Void
  var connectsToNext = false

  var body: some View {
    Group {
      if let meetingID = event.meetingID {
        NavigationLink(value: LibraryRoute.meeting(meetingID)) {
          label
        }
        .buttonStyle(.plain)
      } else {
        Button {
          InteractionFeedback.shared.send(.tap)
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
    JournalTimelineRow(time: event.start < Calendar.current.startOfDay(for: day) ? "継続" : event.start.formatted(date: .omitted, time: .shortened),
      icon: event.meetingID == nil ? .calendar : .waveform, tint: .orange, railColor: .orange,
      connectsToNext: connectsToNext) {
      VStack(alignment: .leading, spacing: 8) {
      Text(timeText)
        .font(.caption.monospacedDigit())

      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(.headline)
        HStack(spacing: 4) {
          Text(event.meetingID == nil ? "予定" : "録音あり")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
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

      if let location = event.location, !location.isEmpty {
        Label(location, icon: .location).font(.subheadline).foregroundStyle(.secondary)
      }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
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
