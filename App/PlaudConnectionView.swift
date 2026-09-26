import SwiftUI

struct PlaudConnectionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isImporterPresented = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Label("PLAUDの記録をMemoraへ", icon: .waveformBadgeMic)
              .font(.headline)
            Text("PLAUDアプリから書き出した音声を保存します。文字起こしと要約は、取り込み後に必要なタイミングで開始できます。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Button("音声を取り込む", icon: .squareAndArrowDown) {
              isImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
          }
          .padding(.vertical, 8)
        }

        Section {
          LabeledContent("Memoraから直接接続", value: "準備中")
        } footer: {
          Text("直接接続にはPLAUD側のアプリ連携設定が必要です。準備が整うまでは音声取り込みを利用できます。")
        }
      }
      .navigationTitle("PLAUDを接続")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
      .fileImporter(
        isPresented: $isImporterPresented,
        allowedContentTypes: [.audio],
        allowsMultipleSelection: false
      ) { result in
        guard case .success(let urls) = result, let url = urls.first else { return }
        dismiss()
        Task {
          await model.importAudio(from: url)
        }
      }
    }
  }
}
