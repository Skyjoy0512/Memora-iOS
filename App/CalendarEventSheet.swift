import EventKit
import SwiftUI
import UIKit

/// One calendar event in full, with a way to start recording it and to open it
/// in the calendar app. It is read from EventKit, never stored.
struct CalendarEventSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  var event: JournalCalendarEvent
  @State private var editing: CalendarEventEditContext?
  @State private var editUnavailable = false
  @State private var showsEditError = false

  var body: some View {
    Group {
      if let editing {
        CalendarEventEditor(editing: editing) {
          model.invalidateAICalendarContext()
          dismiss()
        } onUnavailable: {
          editingBecameUnavailable()
        }
      } else {
        details
      }
    }
    .presentationDetents(editing == nil ? [.medium, .large] : [.large])
    .interactiveDismissDisabled(editing != nil)
    .alert("編集できません", isPresented: $showsEditError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("予定が変更・削除されたか、編集権限が変わりました。カレンダーで現在の状態を確認してください。")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { recheckEditingPermission() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main)) { _ in
      recheckEditingPermission()
    }
  }

  private var details: some View {
    NavigationStack {
      MemoraList {
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
          if offersEditing {
            Button("編集", icon: .pencil) {
              guard let context = CalendarEventEditContext(snapshot: event) else {
                editingBecameUnavailable(); return
              }
              editing = context
            }
          }
          if canStartRecording {
            Button("録音を開始", icon: .waveform) {
              startRecording()
            }
          }
          Button("カレンダーで開く", icon: .calendar) {
            openInCalendar()
          }
        } footer: {
          if !offersEditing {
            Text("この予定はMemoraでは編集できません。カレンダーアプリで確認できます。")
          }
        }
      }
      .navigationTitle("予定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
    }
  }

  private var offersEditing: Bool {
    event.allowsEditing && !editUnavailable && CalendarService.access == .granted
  }

  private func editingBecameUnavailable() {
    editing = nil
    editUnavailable = true
    showsEditError = true
    model.invalidateAICalendarContext()
  }

  private func recheckEditingPermission() {
    if let editing, !editing.isEditable { editingBecameUnavailable() }
    else if CalendarService.access != .granted { editUnavailable = true }
  }

  private var timeText: String {
    if event.isAllDay {
      return "終日"
    }
    let start = event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP")))
    let end = event.end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP")))
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
