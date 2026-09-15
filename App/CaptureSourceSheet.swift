import SwiftUI
import UniformTypeIdentifiers

/// A compact action palette anchored to the main FAB.
struct CaptureSourceSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isFileImporterPresented = false

  var body: some View {
    VStack(spacing: 2) {
      CaptureSourceButton(symbol: "waveform", title: "録音を開始") {
        beginRecording()
      }

      CaptureSourceButton(symbol: "square.and.arrow.down", title: "音声を取り込む") {
        isFileImporterPresented = true
      }

      CaptureSourceButton(symbol: "video", title: "オンライン会議") {
        presentOnlineMeeting()
      }

      Divider()
        .padding(.horizontal, 10)
        .padding(.vertical, 4)

      CaptureSourceButton(symbol: "folder.badge.plus", title: "プロジェクトを作成") {
        presentProjectCreation()
      }
    }
    .padding(10)
    .frame(width: 292)
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.audio],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        dismiss()
        Task {
          try? await Task.sleep(for: .milliseconds(250))
          await model.importAudio(from: url)
        }
      case .failure:
        model.importErrorMessage = "ファイルを選択できませんでした。もう一度お試しください。"
      }
    }
  }

  private func beginRecording() {
    dismiss()
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      await model.startCapture()
    }
  }

  private func presentOnlineMeeting() {
    dismiss()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(250))
      model.isOnlineMeetingCapturePresented = true
    }
  }

  private func presentProjectCreation() {
    dismiss()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(250))
      model.isFileCreationPresented = true
    }
  }
}

private struct CaptureSourceButton: View {
  var symbol: String
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.title3.weight(.semibold))
          .symbolRenderingMode(.monochrome)
          .frame(width: 42, height: 42)
          .background(Color.primary.opacity(0.07), in: Circle())

        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)

        Spacer(minLength: 12)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 54)
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

struct OnlineMeetingCaptureView: View {
  var beginRecording: () -> Void

  var body: some View {
    List {
      Section {
        Label("Zoom", systemImage: "video")
        Label("Google Meet", systemImage: "video")
        Label("Microsoft Teams", systemImage: "video")
      } header: {
        Text("対応する会議")
      } footer: {
        Text("会議をスピーカーで再生し、Memoraをバックグラウンドで録音します。開始前に参加者へ録音を知らせてください。")
      }

      Section {
        Button("録音の準備をする", systemImage: "waveform", action: beginRecording)
      }
    }
    .navigationTitle("オンライン会議")
    .navigationBarTitleDisplayMode(.inline)
  }
}
