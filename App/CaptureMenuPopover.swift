import SwiftUI

/// Shared native Menu/dialog actions; presentation is owned by the system.
struct CaptureMenuPopover: View {
  var spaceID: UUID? = nil
  var includesProjectCreation = false
  var onSelect: (CaptureAction) -> Void
  @Environment(MemoraModel.self) private var model

  var body: some View {
    action(.recording)
    Divider()
    action(.importAudio)
    action(.newMemo)
    Button("資料を追加", icon: .paperclip) {
      model.sourceAddProjectID = spaceID
      model.isSourceAddPresented = true
    }
    .accessibilityHint(spaceID.flatMap { model.space(id: $0)?.name }.map { "保存先：" + $0 } ?? "ライブラリに保存します")
    Divider()
    ForEach(CaptureAction.available.filter { ![.recording, .importAudio, .newMemo].contains($0) }) { item in
      action(item)
    }
    if includesProjectCreation {
      Button("プロジェクトを作成", icon: .folder) { model.isFileCreationPresented = true }
        .disabled(model.isRestoring)
    }
  }

  private func action(_ action: CaptureAction) -> some View {
    Button(action.title, icon: action.symbol) { onSelect(action) }
      .accessibilityHint(action.detail)
  }
}
