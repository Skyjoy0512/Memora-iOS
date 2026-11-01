import SwiftUI

/// Shared native Menu/dialog actions; presentation is owned by the system.
struct CaptureMenuPopover: View {
  var spaceID: UUID? = nil
  var onSelect: (CaptureAction) -> Void
  @Environment(MemoraModel.self) private var model

  var body: some View {
    Button("資料を追加", icon: .paperclip) {
      model.sourceAddProjectID = spaceID
      model.isSourceAddPresented = true
    }
    .accessibilityHint(spaceID.flatMap { model.space(id: $0)?.name }.map { "保存先：" + $0 } ?? "ライブラリに保存します")
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
