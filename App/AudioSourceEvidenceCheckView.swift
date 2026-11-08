#if DEBUG
import SwiftUI

struct AudioSourceEvidenceCheckView: View {
  @Environment(MemoraModel.self) private var model
  @State private var check = AudioSourceEvidenceCheck()

  var body: some View {
    MemoraList {
      Section {
        Text("モデル・外部APIは使いません。時刻付きの字幕ソースを実際に保存し、検索・引用位置・引用リンクを確認します。閉じる際に今回の検証データだけを削除します。")
          .font(.footnote).foregroundStyle(.secondary)
        Button("音声・字幕の引用を検証") { check.start(in: model) }
          .disabled(check.isRunning || model.currentTeamID != nil || model.isRestoring || model.isStoreProtected)
        Text(check.result).textSelection(.enabled)
      }
      Button("検証データを削除", role: .destructive) { check.cleanup(in: model) }
    }
    .navigationTitle("音声・字幕の引用検証").navigationBarTitleDisplayMode(.inline)
    .onDisappear { check.cleanup(in: model) }
  }
}
#endif
