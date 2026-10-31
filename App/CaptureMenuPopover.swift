import SwiftUI

/// Shared native Menu/dialog actions; presentation is owned by the system.
struct CaptureMenuPopover: View {
  var spaceID: UUID? = nil
  var onSelect: (CaptureAction) -> Void
  @Environment(MemoraModel.self) private var model

  var body: some View {
    if let spaceID, let space = model.space(id: spaceID) {
      Button {
        model.sourceAddProjectID = spaceID
      } label: {
        Label("参考資料を追加", icon: .paperclip)
      }
      .accessibilityHint("保存先：\(space.name)。リンク・ファイル・メモを参照資料にします。")
    }
    ForEach(CaptureAction.available) { action in
      Button {
        onSelect(action)
      } label: {
        Label(action.title, icon: action.symbol)
      }
      .accessibilityHint(action.detail)
    }
  }
}
