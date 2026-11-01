import SwiftUI
import UniformTypeIdentifiers

/// The top-right create control. It owns the same capture menu the old bottom
/// bar opened, so recording, import, memos and a new chat stay one tap away.
struct CaptureToolbarButton: View {
  @Environment(MemoraModel.self) private var model
  var spaceID: UUID?
  var tab: RootTab
  @State private var isDialogPresented = false
  @State private var isFileImporterPresented = false
  @State private var importContext: LocalImportContext?

  var body: some View {
    Menu {
      Section("新しい記録") {
        CaptureMenuPopover(spaceID: spaceID, onSelect: select)
      }
    } label: {
      ToolbarActionLabel("新規作成", icon: .plus)
    }
    .accessibilityLabel("新規作成")
    .confirmationDialog("新しい記録", isPresented: $isDialogPresented, titleVisibility: .visible) {
      // Empty-state requests cannot programmatically open a Menu. They use the
      // same actions in a native dialog, with no simulated taps or timers.
      CaptureMenuPopover(spaceID: spaceID, onSelect: select)
    }
    .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.audio]) { result in
      let context = importContext
      importContext = nil
      switch result {
      case .success(let url):
        Task { await model.importInformationFile(url, context: context) }
      case .failure(let error):
        guard (error as NSError).code != NSUserCancelledError else { return }
        model.importErrorMessage = "ファイルを選択できませんでした。もう一度お試しください。"
      }
    }
    .onChange(of: model.isCaptureSourcePresented) { _, presented in
      if !presented {
        isDialogPresented = false
      } else if model.selectedTab == tab && !model.isToolsPresented {
        isDialogPresented = true
      }
    }
    .onChange(of: isDialogPresented) { _, presented in
      if !presented { model.isCaptureSourcePresented = false }
    }
  }

  private func select(_ action: CaptureAction) {
    InteractionFeedback.shared.send(.tap)
    if action == .importAudio {
      importContext = LocalImportContext(projectID: spaceID, in: model)
      guard importContext != nil else {
        model.importErrorMessage = "この保存先には取り込めません。画面を開き直してください。"
        return
      }
      isFileImporterPresented = true
    } else {
      let destinationID = spaceID
      Task { await model.performCaptureMenuAction(action, projectID: destinationID) }
    }
  }
}
