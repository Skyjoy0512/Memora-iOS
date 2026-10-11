import SwiftUI

struct SpeakerIdentificationSettingsView: View {
  var body: some View {
    Form {
      Section("話者識別") {
        Text("音声AIモデルの準備と実機での判定検証が必要です。")
        Text("声のサンプル保存と、声の特徴量による本人識別は別の機能です。本人識別を認証には使いません。")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("話者識別")
    .memoraBackButton()
  }
}
