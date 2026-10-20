import SwiftUI

struct WebResearchSettingsView: View {
  @State private var key = ""
  @State private var hasKey = KeychainStore.has(WebResearchClient.keyName)
  @State private var failure = false
  var body: some View {
    MemoraForm {
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
        Text("「検索して」とチャットで頼むと、質問をBraveへ送って検索します。1回の依頼につき検索1回、AI回答は最大1回。契約に応じて利用料金が発生します。端末の記録・添付は自動で混ぜず、自動再送もしません。キーはキーチェーンへ保存します。")
      }
      Section {
        Link("Brave Search APIの案内", destination: URL(string: "https://brave.com/search/api/")!)
        Text("「箱根の観光情報を検索して」のように送ってください。入力欄の「Webで検索」をオンにして質問することもできます。出典と結果は同じチャットに表示し、プロジェクトに保存できます。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Web検索").navigationBarTitleDisplayMode(.inline)
    .alert("保存できませんでした", isPresented: $failure) { Button("閉じる", role: .cancel) {} }
  }
}
