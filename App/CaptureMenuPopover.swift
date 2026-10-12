import SwiftUI
import UniformTypeIdentifiers

/// The capture choices shown from the tab bar's prominent button.
struct CaptureMenuPopover: View {
  var spaceID: UUID? = nil
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isFileImporterPresented = false
  @State private var importSpaceID: UUID?

  var body: some View {
    VStack(spacing: 2) {
      if let spaceID, let space = model.space(id: spaceID) {
        Label("保存先：\(space.name)", icon: .folder)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
      }
      if let spaceID, model.space(id: spaceID) != nil {
        Button("ソースを追加", icon: .paperclip) {
          collapse()
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
            model.sourceAddProjectID = spaceID
          }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 8)
        .buttonStyle(.plain)
      }
      ForEach(CaptureAction.available) { action in
        Button {
          select(action)
        } label: {
          HStack(spacing: 14) {
            Image(icon: action.symbol)
              .font(.title3.weight(.semibold))
              .symbolRenderingMode(.monochrome)
              .frame(width: 44, height: 44)
              .background(Color.primary.opacity(0.07), in: Circle())

            Text(action.title)
              .font(.body.weight(.semibold))
              .foregroundStyle(.primary)

            Spacer(minLength: 12)
          }
          .padding(.horizontal, 8)
          .frame(maxWidth: .infinity, minHeight: 52)
          .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(10)
    .frame(width: 300)
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
