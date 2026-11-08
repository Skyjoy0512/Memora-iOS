#if DEBUG
import SwiftUI

struct WebSourceEvidenceCheckView: View {
  @Environment(MemoraModel.self) private var model
  @State private var check = WebSourceEvidenceCheck()

  var body: some View {
    MemoraList {
      Section {
        Text("モデル・外部APIを使いません。HTMLの本文抽出、検索、引用リンク、SQLite一致を確認します。外部サイトへは接続しません。閉じる際に今回の検証データだけを削除します。")
          .font(.footnote).foregroundStyle(.secondary)
        Button("Web本文の引用を検証") { check.start(in: model) }
          .disabled(check.isRunning || model.currentTeamID != nil || model.isRestoring || model.isStoreProtected)
        Text(check.result).textSelection(.enabled)
      }
      Button("検証データを削除", role: .destructive) { check.cleanup(in: model) }
    }
    .navigationTitle("Web本文の引用検証").navigationBarTitleDisplayMode(.inline)
    .onDisappear { check.cleanup(in: model) }
  }
}
#endif
