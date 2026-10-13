import SwiftUI

/// Remote MCP servers whose tools the Ask AI agent may use.
struct MCPServersView: View {
  @Environment(MemoraModel.self) private var model
  @State private var editing: MCPServerConfig?

  var body: some View {
    List {
      Section {
        if model.mcpServers.isEmpty {
          Text("まだ接続先がありません")
            .foregroundStyle(.secondary)
        }
        ForEach(model.mcpServers) { server in
          Button {
            editing = server
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(server.name)
                  .font(.body.weight(.medium))
                  .foregroundStyle(server.isEnabled ? .primary : .secondary)
                Spacer()
                if !server.isEnabled {
                  Text("オフ").font(.caption).foregroundStyle(.secondary)
                }
              }
              Text(server.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("削除", icon: .trash, role: .destructive) {
              model.deleteMCPServer(server.id)
            }
          }
        }
        Button("接続先を追加", icon: .plus) {
          editing = MCPServerConfig(id: UUID(), name: "", url: "")
        }
      } header: {
        Text("Ask AIで使う外部ツール")
      } footer: {
        Text("MCP（Model Context Protocol）に対応したサーバーをつなぐと、Ask AIのエージェントがその道具を使えます。例: Notion・Linear・社内システム。確認した無料の読み取りツールのみ自動許可できます。料金が不明な操作・変更・外部への記録送信は実行前に確認します。クラウドのAIを使うときだけ利用できます。")
      }

      Section {
        NavigationLink {
          MCPSettingsView()
        } label: {
          LabeledContent {
            Text(MCPIntegration.isConfigured ? "設定済み" : "未設定")
          } label: {
            SettingsLabel("Memoraへの接続", icon: .plugsConnected, color: .mint, artwork: .settingsMCP)
          }
        }
      } header: {
        Text("他のAIからMemoraを使う")
      } footer: {
        Text("ChatGPTやClaudeなどに公開する内容を設定します。公開用のMCPサーバーは未接続で、ここでは接続先と公開範囲を保存します。")
      }
    }
    .navigationTitle("MCP")
    .navigationBarTitleDisplayMode(.inline)
    .memoraBackButton()
    .sheet(item: $editing) { server in
      MCPServerEditor(server: server)
    }
  }
}
