import SwiftUI

struct StateGalleryView: View {
  var body: some View {
    List {
      Section("権限と録音") {
        StateExampleRow(
          symbol: "mic.slash",
          title: "マイクを使えません",
          detail: "設定を開く · 録音以外は利用可能",
          tint: .red
        )
        StateExampleRow(
          symbol: "exclamationmark.triangle",
          title: "録音を開始できませんでした",
          detail: "入力を確認して再試行",
          tint: .orange
        )
      }

      Section("読み込みと処理") {
        StateExampleRow(
          symbol: "arrow.down.doc",
          title: "音声を読み込み中",
          detail: "62% · 完了後に文字起こしを開始",
          tint: .primary,
          progress: 0.62
        )
        StateExampleRow(
          symbol: "text.bubble",
          title: "文字起こし中",
          detail: "完成した発言から利用可能",
          tint: .primary,
          progress: 0.38
        )
        StateExampleRow(
          symbol: "exclamationmark.triangle",
          title: "AI整理だけ未完了",
          detail: "文字起こしはそのまま利用できます",
          tint: .orange
        )
      }

      Section("接続と設定") {
        StateExampleRow(
          symbol: "wifi.slash",
          title: "ネットワークに接続できません",
          detail: "ローカル処理は継続 · AI整理は後で再試行",
          tint: .orange
        )
        StateExampleRow(
          symbol: "key",
          title: "APIキーが未設定です",
          detail: "Memoraの自動設定を使うか、設定で追加",
          tint: .secondary
        )
      }

      Section("Empty") {
        StateExampleRow(
          symbol: "waveform",
          title: "会議が0件",
          detail: "録音または音声インポートへ案内",
          tint: .primary
        )
        StateExampleRow(
          symbol: "checkmark.square",
          title: "タスクが0件",
          detail: "会話から見つかると自動で集約",
          tint: .primary
        )
        StateExampleRow(
          symbol: "sparkles",
          title: "AI履歴が0件",
          detail: "質問例から最初の検索へ案内",
          tint: .primary
        )
      }
    }
    .navigationTitle("状態と復旧")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct StateExampleRow: View {
  var symbol: String
  var title: String
  var detail: String
  var tint: Color
  var progress: Double?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.body.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let progress {
          ProgressView(value: progress)
            .tint(tint)
        }
      }
    }
    .padding(.vertical, 5)
  }
}
