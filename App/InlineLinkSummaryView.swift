import SwiftUI

/// Inline references use the same saved source and summary as Library.
struct InlineLinkSummaryView: View {
  @Environment(MemoraModel.self) private var model
  @Binding var text: String
  var isComposing = false
  @State private var urls: [URL] = []
  @State private var savedID: UUID?
  @State private var failure: String?
  @State private var editorInput = ComposerInputState()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let id = savedID, model.source(id: id) != nil {
        NavigationLink("リンク先の資料を開く") { ProjectSourceDetailView(sourceID: id) }.frame(minHeight: 44)
      } else if let url = urls.first {
        Button("リンク先を資料に追加", icon: .link) {
          Task {
            do { savedID = try await model.addProjectLink(url.absoluteString, projectID: model.visibleProjectID) }
            catch { failure = error.localizedDescription }
          }
        }
        .frame(minHeight: 44)
        .disabled(model.currentTeamID != nil || model.isRestoring || model.isStoreProtected)
      }
      if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { ComposerInputObserver(state: editorInput, isActive: !urls.isEmpty) }
    .task(id: text) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled, !isComposing, editorInput.snapshot()?.hasMarkedText != true else { return }
      let detected = InlineURLDetector.urls(in: text)
      if urls != detected { savedID = nil; failure = nil }
      urls = detected
    }
    .onChange(of: model.aiWorkspaceGeneration) { _, _ in savedID = nil; urls = []; failure = nil }
  }
}
