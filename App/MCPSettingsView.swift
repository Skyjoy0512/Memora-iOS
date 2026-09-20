import SwiftUI

/// Prepares the connection that lets an outside assistant — ChatGPT, Claude,
/// and the like — read Memora over MCP. The server itself lives outside this
/// app, so this screen only stores the endpoint, token, and scope.
struct MCPSettingsView: View {
  @State private var token = ""
  @State private var hasToken = false
  @AppStorage(MCPIntegration.serverURLKey) private var serverURL = MCPIntegration.defaultServerURL
  @AppStorage("memora.mcpShareSummaries") private var sharesSummaries = true
  @AppStorage("memora.mcpShareTranscripts") private var sharesTranscripts = false
  @AppStorage("memora.mcpShareJournal") private var sharesJournal = true

  var body: some View {
    Form {
      Section {
        LabeledContent("状態", value: hasToken ? "設定済み" : "未設定")
      } header: {
        Text("接続")
      } footer: {
        Text("MCPサーバーの実装はこのアプリの範囲外です。ChatGPTなどから呼ぶには、公開したサーバーとトークンが必要です。")
      }

      Section {
        TextField("サーバーURL", text: $serverURL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)

        SecureField("アクセストークン", text: $token)
          .textContentType(.password)

        Button("トークンを保存") {
          KeychainStore.set(token, forKey: MCPIntegration.tokenKey)
          token = ""
          hasToken = MCPIntegration.isConfigured
        }
        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)

        if hasToken {
          Button("トークンを削除", systemImage: "trash", role: .destructive) {
            KeychainStore.set(nil, forKey: MCPIntegration.tokenKey)
            hasToken = false
          }
        }
      } header: {
        Text("サーバー")
      } footer: {
        Text("トークンはキーチェーンに保存し、画面には残しません。")
      }

      Section {
        Toggle("会議の要約", isOn: $sharesSummaries)
        Toggle("文字起こし", isOn: $sharesTranscripts)
        Toggle("ジャーナル", isOn: $sharesJournal)
      } header: {
        Text("公開する内容")
      } footer: {
        Text("オフにした内容はMCPの応答に含めません。")
      }

      Section {
        Text("例:「今週の決定事項をまとめて」とChatGPTで聞くと、許可した範囲だけをMemoraから読み取ります。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("ChatGPT (MCP)")
    .memoraBackButton()
    .onAppear {
      hasToken = MCPIntegration.isConfigured
    }
  }
}
