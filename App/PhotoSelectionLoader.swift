import PhotosUI
import SwiftUI
import ImageIO

struct PhotoSelectionLoader: ViewModifier {
  @Environment(MemoraModel.self) private var model
  @Binding var selection: PhotosPickerItem?
  @Binding var isLoading: Bool
  var onLoaded: (Data) -> Void
  @State private var failure = false
  @State private var attempt = 0

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if isLoading {
          ProgressView("写真を読み込んでいます…")
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding().allowsHitTesting(false)
        }
      }
      .task(id: Request(item: selection, attempt: attempt)) {
        guard let item = selection else { isLoading = false; return }
        let workspace = model.currentTeamID, generation = model.aiWorkspaceGeneration
        isLoading = true
        defer { if !Task.isCancelled, selection == item { isLoading = false } }
        do {
          guard let data = try await item.loadTransferable(type: Data.self),
                CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            throw CocoaError(.fileReadCorruptFile)
          }
          guard !Task.isCancelled, selection == item,
                workspace == model.currentTeamID, generation == model.aiWorkspaceGeneration else { return }
          onLoaded(data)
          selection = nil
          isLoading = false
        } catch {
          guard !Task.isCancelled, !(error is CancellationError),
                (error as NSError).code != NSUserCancelledError,
                selection == item, workspace == model.currentTeamID,
                generation == model.aiWorkspaceGeneration else { return }
          failure = true
        }
      }
      .onDisappear { isLoading = false }
      .alert("写真を読み込めませんでした", isPresented: $failure) {
        Button("再試行") { attempt += 1 }
        Button("閉じる", role: .cancel) { selection = nil }
      } message: { Text("写真はまだ追加されていません。通信状態を確認するか、別の写真を選んでください。入力内容はこの画面に残っています。") }
  }

  private struct Request: Hashable {
    var item: PhotosPickerItem?
    var attempt: Int
  }
}

extension View {
  func loadsSelectedPhoto(_ selection: Binding<PhotosPickerItem?>, isLoading: Binding<Bool>,
                          onLoaded: @escaping (Data) -> Void) -> some View {
    modifier(PhotoSelectionLoader(selection: selection, isLoading: isLoading, onLoaded: onLoaded))
  }
}
