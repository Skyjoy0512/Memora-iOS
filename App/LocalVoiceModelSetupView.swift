import SwiftUI

struct LocalVoiceModelSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var store = LocalVoiceModelStore.shared
  var onStart: (() -> Void)?

  var body: some View {
    Form {
      Section {
        LabeledContent("会話モデル", value: LocalVoiceModel.name)
        LabeledContent("保存容量", value: "約1.33 GB")
        LabeledContent("状態", value: store.isInstalled ? "導入済み" : store.isVerifying ? "検証中" : store.isDownloading ? "ダウンロード中" : "未導入")
      } footer: {
        Text("会話はこのiPhone内で処理します。APIキーは不要です。初回のモデル取得にはインターネット接続が必要です。日本語の音声認識と読み上げは端末内の音声機能を使います。")
      }
      Section {
        if store.isDownloading {
          if store.isVerifying {
            ProgressView("モデルを検証しています…")
          } else {
            ProgressView(value: store.progress) {
              Text("ダウンロード中")
            } currentValueLabel: {
              Text(store.progress, format: .percent.precision(.fractionLength(0)))
            }
          }
          Button("ダウンロードをキャンセル", role: .cancel) { store.cancel() }
        } else if !store.isInstalled {
          Button("モデルをダウンロード（約1.33 GB）") { store.install() }
            .accessibilityIdentifier("live.model.download")
        } else if let onStart {
          Button("Liveを開始", action: onStart)
            .accessibilityIdentifier("live.model.start")
        }
        if let message = store.errorMessage {
          Text(message).foregroundStyle(.secondary)
        }
      } footer: {
        if !store.isInstalled { Text("Wi-Fiでのダウンロードをおすすめします。途中で閉じてもダウンロードは続きます。") }
      }
      Section {
        Link("モデルの情報とライセンス", destination: URL(string: "https://huggingface.co/Qwen/Qwen3.5-2B")!)
      }
    }
    .navigationTitle("ローカル音声会話")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
      }
    }
  }
}
