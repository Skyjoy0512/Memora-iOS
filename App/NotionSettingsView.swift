import SwiftUI

struct NotionSettingsView: View {
  @AppStorage("memora.notionPageID") private var pageID = ""
  @State private var token = ""
  @State private var hasToken = false

  var body: some View {
    MemoraForm {
      Section {
        HStack(spacing: 12) {
          SettingsIcon(icon: .key)
          SecureField("インテグレーショントークン", text: $token)
            .textContentType(.password)
        }

        Button("トークンを保存", icon: .checkmark) {
          KeychainStore.set(token, forKey: "integration.notion")
          token = ""
          hasToken = KeychainStore.has("integration.notion")
        }
        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)

        if hasToken {
          Button("トークンを削除", icon: .trash, role: .destructive) {
            KeychainStore.set(nil, forKey: "integration.notion")
            hasToken = false
          }
        }
      } header: {
        Text("インテグレーション")
      } footer: {
        Text("Notionで作成したインテグレーションのトークンをキーチェーンに保存します。")
      }

      Section {
        HStack(spacing: 12) {
          SettingsIcon(icon: .docText)
          TextField("ページID または データベースID", text: $pageID)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      } header: {
        Text("保存先")
      } footer: {
        Text("対象のページをインテグレーションに接続（共有）しておいてください。")
      }

      Section {
        SettingsValue(title: "状態", value: hasToken && !pageID.isEmpty ? "設定済み" : "未設定", icon: .plugsConnected)
      }
    }
    .navigationTitle("Notion")
    .memoraBackButton()
    .onAppear {
      hasToken = KeychainStore.has("integration.notion")
    }
  }
}
