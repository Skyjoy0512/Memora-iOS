import SwiftUI

/// The coming calendar events as a horizontally paging row. Tapping one asks
/// how to record it, since an event can be held in a room or on the web.
struct UpcomingEventsRow: View {
  var meetings: [UpcomingMeeting]
  var onRecordInPerson: (UpcomingMeeting) -> Void
  var onRecordOnline: (UpcomingMeeting) -> Void

  @Environment(MemoraModel.self) private var model
  @State private var chosenMeeting: UpcomingMeeting?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("次のイベント")
        .font(.title3.bold())
        .padding(.horizontal, 18)
        .accessibilityAddTraits(.isHeader)

      ScrollView(.horizontal) {
        LazyHStack(spacing: 10) {
          ForEach(meetings) { meeting in
            Button {
              chosenMeeting = meeting
            } label: {
              UpcomingEventCard(meeting: meeting)
            }
            .buttonStyle(.plain)
            .accessibilityHint("録音方法を選びます")
            // One card fills most of the width, so the next one peeks in and
            // shows there is more to swipe to.
            .containerRelativeFrame(.horizontal) { width, _ in
              meetings.count > 1 ? width * 0.86 : width
            }
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
      .contentMargins(.horizontal, 18, for: .scrollContent)
    }
    .sheet(item: $chosenMeeting) { meeting in
      RecordingMethodSheet(meeting: meeting, onChoose: { method in
        chosenMeeting = nil
        // Recording presents its own screen, so it waits for this sheet to
        // finish closing.
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(350))
          switch method {
          case .inPerson: onRecordInPerson(meeting)
          case .online: onRecordOnline(meeting)
          }
        }
      }, onOpenRecord: { recordID in
        chosenMeeting = nil
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(350))
          model.libraryPath.append(.meeting(recordID))
        }
      })
    }
  }
}
