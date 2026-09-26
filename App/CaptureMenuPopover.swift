import SwiftUI
import UniformTypeIdentifiers

/// The capture choices shown from the tab bar's prominent button.
struct CaptureMenuPopover: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isFileImporterPresented = false

  var body: some View {
    VStack(spacing: 2) {
      ForEach(CaptureAction.allCases) { action in
        // A break between capturing a conversation and adding to the journal.
        if action == .lifeLog {
          Divider()
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }

        Button {
          select(action)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: action.symbol)
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
    switch action {
    case .recording:
      collapse()
      Task {
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        await model.startCapture()
      }
    case .importAudio:
      isFileImporterPresented = true
    case .onlineMeeting:
      collapse()
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        model.isOnlineMeetingCapturePresented = true
      }
    case .lifeLog:
      collapse()
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        model.isLifeLogCreationPresented = true
      }
    case .project:
      collapse()
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
        model.isFileCreationPresented = true
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
      Task {
        await model.importAudio(from: url)
      }
    case .failure:
      model.importErrorMessage = "ファイルを選択できませんでした。もう一度お試しください。"
    }
  }
}
