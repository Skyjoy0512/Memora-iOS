import SwiftUI

/// The coming calendar events as a horizontally paging row. Tapping one asks
/// how to record it, since an event can be held in a room or on the web.
struct UpcomingEventsRow: View {
  var meetings: [UpcomingMeeting]
  var onRecordInPerson: (UpcomingMeeting, LocalImportContext) -> Void
  var onRecordOnline: (UpcomingMeeting) -> Void

  @Environment(MemoraModel.self) private var model
  @State private var chosenMeeting: UpcomingMeeting?
  @State private var pendingAction: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("次のイベント")
        .font(.title3.bold())
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
            .containerRelativeFrame(.horizontal)
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
    }
    .padding(.horizontal, ProjectLayout.horizontalInset)
    .sheet(item: $chosenMeeting, onDismiss: finishDismissal) { meeting in
      RecordingMethodSheet(meeting: meeting, onChoose: { method in
        let context = LocalImportContext(in: model)
        pendingAction = {
          guard let context, context.isCurrent(in: model) else {
            model.recordingErrorMessage = "この保存先では録音できません。画面を開き直してください。"
            return
          }
          switch method {
          case .inPerson: onRecordInPerson(meeting, context)
          case .online:
            if FeatureFlags.isOnlineMeetingCaptureEnabled { onRecordOnline(meeting) }
          }
        }
        chosenMeeting = nil
      }, onOpenRecord: { recordID in
        let generation = model.aiWorkspaceGeneration
        pendingAction = {
          guard model.aiWorkspaceGeneration == generation else { return }
          model.libraryPath.append(.meeting(recordID))
        }
        chosenMeeting = nil
      })
    }
  }

  private func finishDismissal() {
    // Native dismissal settles the presenting sheet before another screen opens.
    let action = pendingAction
    pendingAction = nil
    action?()
  }
}
