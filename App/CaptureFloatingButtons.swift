import SwiftUI
import UniformTypeIdentifiers

/// A shared creation menu beside the Ask AI field. Presentation
/// stays mounted while typing so a file picker cannot disappear with its label.
struct CaptureFloatingButtons: View {
  @Environment(MemoraModel.self) private var model
  var spaceID: UUID?
  var isVisible = true
  var includesProjectCreation = false
  var onOpenCaptureMenu: () -> Void = {}
  @State private var isDialogPresented = false
  @State private var isFileImporterPresented = false
  @State private var importContext: LocalImportContext?

  var body: some View {
    // The presentation host survives keyboard/picker changes. Only the visual
    // menus are removed, with no native-glass fade or zero-size interpolation.
    Color.clear
      .frame(width: 52, height: 52)
      .overlay {
        if isVisible { menus.transition(.identity) }
      }
      .transaction {
        $0.animation = nil
        $0.disablesAnimations = true
      }
      .buttonStyle(.plain)
      .tint(MemoraPalette.textPrimary)
      .disabled(model.isRestoring || model.isStoreProtected || model.currentTeamID != nil)
      .confirmationDialog("新しいファイル", isPresented: $isDialogPresented, titleVisibility: .visible) {
        CaptureMenuPopover(spaceID: spaceID, includesProjectCreation: includesProjectCreation, onSelect: select)
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
        } else if !model.isToolsPresented {
          isDialogPresented = true
        }
      }
      .onChange(of: isDialogPresented) { _, presented in
        if !presented { model.isCaptureSourcePresented = false }
      }
  }

  private var menus: some View {
    Button(action: onOpenCaptureMenu) {
      menuLabel("追加メニュー", icon: .plus)
    }
    .buttonStyle(.plain)
  }

  private func menuLabel(_ title: LocalizedStringKey, icon: MemoraIcon) -> some View {
    Label(title, icon: icon, size: 22)
      .labelStyle(.iconOnly)
      .frame(width: 52, height: 52)
      .contentShape(Circle())
      .memoraGlass(in: Circle(), interactive: true, backed: false)
  }

  private func select(_ action: CaptureAction) {
    InteractionFeedback.shared.send(.tap)
    if action == .newChat, let spaceID {
      if let id = model.createProjectChat(projectID: spaceID) { model.openProjectChat(id) }
    } else if action == .importAudio {
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
