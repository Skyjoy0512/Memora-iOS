import SwiftUI
import UniformTypeIdentifiers

struct CaptureSourceSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isFileImporterPresented = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          Button {
            beginRecording()
          } label: {
            CaptureSourceRow(
              symbol: "waveform",
              title: "録音を開始",
              detail: "マイクからすぐに記録"
            )
          }

          Button {
            isFileImporterPresented = true
          } label: {
            CaptureSourceRow(
              symbol: "square.and.arrow.down",
              title: "音声をインポート",
              detail: "Filesから既存の音声を追加"
            )
          }

          NavigationLink {
            OnlineMeetingCaptureView(beginRecording: beginRecording)
          } label: {
            CaptureSourceRow(
              symbol: "video",
              title: "オンライン会議をキャプチャ",
              detail: "Zoom、Meet、Teamsなど"
            )
          }

          Button {
            dismiss()
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(250))
              model.isFileCreationPresented = true
            }
          } label: {
            CaptureSourceRow(
              symbol: "folder.badge.plus",
              title: "プロジェクトを作成",
              detail: "関連する議事録をまとめる"
            )
          }
        }
      }
      .navigationTitle("新しく追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
      }
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
    .presentationDetents([.medium, .large])
  }

  private func beginRecording() {
    dismiss()
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      await model.startCapture()
    }
  }
}

private struct CaptureSourceRow: View {
  var symbol: String
  var title: String
  var detail: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 6)
    } icon: {
      MemoraIconBadge(symbol: symbol)
    }
  }
}

private struct OnlineMeetingCaptureView: View {
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
