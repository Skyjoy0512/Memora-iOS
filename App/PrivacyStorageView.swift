import SwiftUI

struct PrivacyStorageView: View {
  @Environment(MemoraModel.self) private var model

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
          Image(icon: .iphone)
            .foregroundStyle(.primary)
        }
      } header: {
        Text("基本の保存先")
      } footer: {
        Text("既定では端末だけに保存します。")
      }

      Section {
        Toggle(isOn: Binding(
            get: { model.cloudStorageEnabled },
            set: { model.setCloudStorageEnabled($0) }
          )) {
            SettingsLabel("クラウドに保管", icon: .cloud, color: .blue)
          }
        .disabled(!model.isSubscribed)

        if !model.isSubscribed {
          Button("Memora Plus で利用する", icon: .crown) {
            model.isPaywallPresented = true
          }
        }
      } header: {
        Text("クラウド保管")
      } footer: {
        Text(model.isSubscribed
             ? "オンにすると、録音・文字起こし・議事録をクラウドにも保管します。端末からはいつでも削除できます。"
             : "クラウド保管はMemora Plusの機能です。")
      }

      Section {
        SettingsValue(title: "高度なAI整理", value: "実行前に表示", icon: .sparkles, color: .purple)
        SettingsValue(title: "クラウド保管", value: model.cloudStorageEnabled ? "オン" : "オフ", icon: .cloud, color: .blue)
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
