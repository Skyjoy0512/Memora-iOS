import SwiftUI

struct PrivacyStorageView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    MemoraForm {
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
          Image(icon: .iphone)
            .foregroundStyle(.primary)
        }
      } header: {
        Text("基本の保存先")
      } footer: {
        Text("既定では端末だけに保存します。")
      }

      Section {
        SettingsValue(title: "クラウドに保管", value: model.cloudStorageStatus, icon: .cloud)
      } header: {
        Text("クラウド保管")
      } footer: {
        Text("クラウド保管はまだ接続されていません。記録はこのiPhoneに保存されます。機種変更や端末の紛失に備えて、設定の「バックアップ」から書き出してください。")
      }

      Section {
        SettingsValue(title: "クラウドAI（BYOK）", value: "設定したサービス", icon: .sparkles)
        SettingsValue(title: "クラウド保管", value: model.cloudStorageStatus, icon: .cloud)
      } header: {
        Text("外部へ送られる可能性があるもの")
      } footer: {
        Text("クラウドAIを選ぶと、回答に必要な記録のテキストを設定したサービスへ送信します。場所の自動記録・位置情報の項目はAIへ渡しません。自分でメモに書いた場所名などは、本文の一部として送信されることがあります。")
      }
    }
    .navigationTitle("データの保存先")
    .memoraBackButton()
  }
}
