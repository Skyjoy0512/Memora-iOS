import SwiftUI

struct WebResearchSettingsView: View {
  @State private var key = ""
  @State private var hasKey = KeychainStore.has(WebResearchClient.keyName)
  @State private var failure = false
  var body: some View {
    Form {
      Section {
        Text(hasKey ? "APIキー登録済み" : "APIキー未登録").foregroundStyle(.secondary)
        SecureField("APIキー", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
        Button("キーを保存") {
          if KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: WebResearchClient.keyName) {
            key = ""; hasKey = true
          } else { failure = true }
        }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if hasKey { Button("キーを削除", role: .destructive) {
          if KeychainStore.set(nil, forKey: WebResearchClient.keyName) { hasKey = false } else { failure = true }
        } }
      } header: { Text("Brave Search API") } footer: {
        Text("キーはキーチェーンへ保存します。検索語はBraveへ送られ、契約に応じて利用料金が発生します。自動調査や自動再送は行いません。")
      }
      Section {
        Link("Brave Search APIの案内", destination: URL(string: "https://brave.com/search/api/")!)
        Text("Deep Researchは最大3つの検索API抽出結果を比較します。全ページの全文調査を保証するものではありません。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Web検索").navigationBarTitleDisplayMode(.inline)
    .alert("保存できませんでした", isPresented: $failure) { Button("閉じる", role: .cancel) {} }
  }
}
