import SwiftUI

/// The top-right create control. It owns the same capture menu the old bottom
/// bar opened, so recording, import, memos and a new chat stay one tap away.
struct CaptureToolbarButton: View {
  @Environment(MemoraModel.self) private var model
  var spaceID: UUID?
  var tab: RootTab
  @State private var isPopoverPresented = false
  @Namespace private var presentationNamespace

  var body: some View {
    ToolbarIconButton("新規作成", icon: .plus) {
      InteractionFeedback.shared.send(.tap)
      model.isCaptureSourcePresented = true
    }
    .matchedTransitionSource(id: "capture-menu", in: presentationNamespace)
    .popover(isPresented: $isPopoverPresented) {
      CaptureMenuPopover(spaceID: spaceID)
        .presentationCompactAdaptation(.popover)
        .navigationTransition(.zoom(sourceID: "capture-menu", in: presentationNamespace))
    }
    .onChange(of: model.isCaptureSourcePresented) { _, presented in
      // TabView keeps inactive toolbars alive; only the visible source presents.
      if !presented {
        isPopoverPresented = false
      } else if model.selectedTab == tab && !model.isToolsPresented {
        isPopoverPresented = true
      }
    }
    .onChange(of: isPopoverPresented) { _, presented in
      if !presented { model.isCaptureSourcePresented = false }
    }
  }
}
