import SwiftUI

/// Shared native Menu/dialog actions; presentation is owned by the system.
struct CaptureMenuPopover: View {
  var spaceID: UUID? = nil
  var group: CaptureMenuGroup = .all
  var includesProjectCreation = false
  var onSelect: (CaptureAction) -> Void
  @Environment(MemoraModel.self) private var model

  var body: some View {
    switch group {
    case .notes:
      action(.newMemo)
    case .recording:
      action(.recording)
      action(.importAudio)
      action(.onlineMeeting)
    case .all:
      action(.recording)
      Divider()
      action(.importAudio)
      action(.newMemo)
      Divider()
      ForEach(CaptureAction.available.filter { ![.recording, .importAudio, .newMemo].contains($0) }) { item in
        action(item)
      }
      if includesProjectCreation {
        Button("プロジェクトを作成", icon: .folder) { model.isFileCreationPresented = true }
          .disabled(model.isRestoring)
      }
    }
  }

  private func action(_ action: CaptureAction) -> some View {
    Button(action.title, icon: action.symbol) { onSelect(action) }
      .accessibilityHint(action.detail)
  }
}
