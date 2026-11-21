import SwiftUI

/// One calendar event in the journal's day timeline. A recording tied to the
/// event opens the record; other events open their own detail.
struct JournalCalendarEventRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  /// The day being shown, so an event that began the night before reads as a
  /// continuation.
  var day: Date
  var event: JournalCalendarEvent
  var onOpen: (JournalCalendarEvent) -> Void
  var connectsToNext = false
  var nextDate: Date?

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
    JournalTimelineRow(time: event.start < Calendar.current.startOfDay(for: day) ? "継続" : event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP"))),
      date: max(event.start, Calendar.current.startOfDay(for: day)),
      icon: event.meetingID == nil ? .calendar : .waveform,
      connectsToNext: connectsToNext, nextDate: nextDate) {
      VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
        Text(timeText)
          .font(MemoraTypography.metadata.monospacedDigit())
          .foregroundStyle(.secondary)
        Text(event.title)
          .font(MemoraTypography.body.weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
        let details = typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
          : AnyLayout(HStackLayout(spacing: MemoraSpacing.sm))
        details {
          Text(event.meetingID == nil ? "予定" : "録音あり")
            .fontWeight(.medium)
          HStack(spacing: MemoraSpacing.xs) {
            if let color = event.calendarColor {
              Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(event.calendarTitle).fixedSize(horizontal: false, vertical: true)
          }
        }
        .font(MemoraTypography.metadata)
        .foregroundStyle(.secondary)
        if let location = event.location, !location.isEmpty {
          Label(location, icon: .location)
            .font(MemoraTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
    let end = event.end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP")))
    if event.start < dayStart {
      return "〜\(end)"
    }
    return "\(event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP"))))〜\(end)"
  }
}
