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
      } footer: {
        Text("MCP（Model Context Protocol）に対応したサーバーをつなぐと、Ask AIのエージェントがその道具を使えます。例: Notion・Linear・社内システム。読み取り専用の道具はすぐ実行し、それ以外は実行前に確認します。クラウドのAIを使うときだけ利用できます。")
      }
    }
    .navigationTitle("MCPサーバー")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { server in
      MCPServerEditor(server: server)
    }
  }
}
