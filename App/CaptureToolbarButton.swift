import SwiftUI

/// The top-right create control. It owns the same capture menu the old bottom
/// bar opened, so recording, import, memos and a new chat stay one tap away.
struct CaptureToolbarButton: View {
  @Environment(MemoraModel.self) private var model
  var spaceID: UUID?

  var body: some View {
    @Bindable var model = model

    ToolbarIconButton("新規作成", icon: .plus) {
      InteractionFeedback.shared.send(.tap)
      model.isCaptureSourcePresented = true
    }
    .popover(isPresented: $model.isCaptureSourcePresented) {
      CaptureMenuPopover(spaceID: spaceID)
        .presentationCompactAdaptation(.popover)
    }
  }
}
