import SwiftUI
import UniformTypeIdentifiers

/// The capture choices shown from the tab bar's prominent button.
struct CaptureMenuPopover: View {
  var spaceID: UUID? = nil
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isFileImporterPresented = false
  @State private var importSpaceID: UUID?
  @State private var contentHeight: CGFloat = 300

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text("新しい記録")
          .font(MemoraTypography.metadata.weight(.medium))
          .foregroundStyle(MemoraPalette.textSecondary)
          .padding(.horizontal, MemoraSpacing.sm)
          .padding(.vertical, MemoraSpacing.sm)
        if let spaceID, let space = model.space(id: spaceID) {
          Label("保存先：\(space.name)", icon: .folder)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoraSpacing.sm)
        }
        if let spaceID, model.space(id: spaceID) != nil {
          Button {
            collapse()
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
              model.sourceAddProjectID = spaceID
            }
          } label: {
            MemoraActionLabel(title: "ソースを追加", detail: "リンク・ファイル・メモを参照資料にします。", icon: .paperclip)
          }
          .accessibilityLabel("ソースを追加")
        }
        ForEach(CaptureAction.available) { action in
          Button {
            select(action)
          } label: {
            MemoraActionLabel(title: action.title, detail: action.detail, icon: action.symbol)
          }
          .accessibilityLabel(action.title)
          .accessibilityHint(action.detail)
        }
      }
      .padding(MemoraSpacing.md)
      .buttonStyle(MemoraMenuButtonStyle())
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
        if abs(contentHeight - height) > 0.5 { contentHeight = height }
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(idealWidth: 320, maxWidth: 360)
    .frame(idealHeight: min(contentHeight, 480), maxHeight: min(contentHeight, 480))
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.audio],
      allowsMultipleSelection: false,
      onCompletion: handleAudioImport
    )
  }

  private func select(_ action: CaptureAction) {
    InteractionFeedback.shared.send(.tap)
    let destinationID = spaceID
    switch action {
    case .recording:
      collapse()
      Task {
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        await model.startCapture(spaceID: destinationID)
      }
    case .importAudio:
      importSpaceID = destinationID
      isFileImporterPresented = true
    case .phoneCall:
      collapse()
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        model.openCalling()
      }
    case .onlineMeeting:
      model.onlineMeetingCaptureSpaceID = destinationID
      collapse()
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        model.isOnlineMeetingCapturePresented = true
      }
    }
  }

  private func collapse() {
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
      model.isCaptureSourcePresented = false
    }
  }

  private func handleAudioImport(_ result: Result<[URL], any Error>) {
    collapse()
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      let destinationID = importSpaceID
      Task {
        await model.importAudio(from: url, spaceID: destinationID)
      }
    case .failure:
      model.importErrorMessage = "ファイルを選択できませんでした。もう一度お試しください。"
    }
  }
}
