import SwiftUI

struct PrivacyStorageView: View {
  var body: some View {
    List {
      Section {
        Label {
          VStack(alignment: .leading, spacing: 4) {
            Text("このiPhone")
              .font(.headline)
            Text("録音・文字起こし・議事録を保存")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "iphone")
            .foregroundStyle(.primary)
        }
      }

      Section {
        LabeledContent("高度なAI整理", value: "実行前に表示")
        LabeledContent("クラウド同期", value: "オフ")
      } header: {
        Text("外部へ送られる可能性があるもの")
      } footer: {
        Text("処理先が変わる時だけ、操作の流れを止めない形で確認します。")
      }
    }
    .navigationTitle("データの保存先")
    .memoraBackButton()
  }
}
