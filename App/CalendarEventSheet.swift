import SwiftUI
import UIKit

/// One calendar event in full, with a way to start recording it and to open it
/// in the calendar app. It is read from EventKit, never stored.
struct CalendarEventSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  var event: JournalCalendarEvent

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(event.title)
            .font(.title3.bold())
        }

        Section {
          LabeledContent("時刻", value: timeText)
          if let location = event.location, !location.isEmpty {
            LabeledContent("場所", value: location)
          }
          LabeledContent("カレンダー", value: event.calendarTitle)
        }

        Section {
          if canStartRecording {
            Button("録音を開始", systemImage: "waveform") {
              startRecording()
            }
          }
          Button("カレンダーで開く", systemImage: "calendar") {
            openInCalendar()
          }
        }
      }
      .navigationTitle("予定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
  }

  private var timeText: String {
    if event.isAllDay {
      return "終日"
    }
    let start = event.start.formatted(date: .omitted, time: .shortened)
    let end = event.end.formatted(date: .omitted, time: .shortened)
    return "\(start)〜\(end)"
  }

  /// Recording is offered from fifteen minutes before the event until it ends.
  private var canStartRecording: Bool {
    let now = Date.now
    return now >= event.start.addingTimeInterval(-15 * 60) && now <= event.end
  }

  private func startRecording() {
    let meeting = UpcomingMeeting(
      id: event.eventIdentifier,
      title: event.title,
      start: event.start,
      end: event.end
    )
    Task {
      await model.startCapture(event: meeting)
    }
    dismiss()
  }

  private func openInCalendar() {
    // calshow: opens the calendar app at the given time.
    guard let url = URL(string: "calshow:\(event.start.timeIntervalSinceReferenceDate)") else { return }
    openURL(url)
  }
}
