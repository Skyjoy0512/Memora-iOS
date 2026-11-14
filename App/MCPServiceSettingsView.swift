import SwiftUI

struct MCPServiceSettingsView: View {
  @Environment(MemoraModel.self) private var model
  var preset: MCPServerConfig.Preset
  @State private var editing: MCPServerConfig?

  var body: some View {
    let servers = model.mcpServers.filter { $0.validatedPreset == preset }
    MemoraForm {
      Section {
        Text(preset.tokenGuidance)
        Link("公式の接続ガイド", destination: preset.documentationURL)
      } footer: {
        Text("読み取り専用です。接続確認は外部サービスへ通信します。トークンはキーチェーンに保存します。")
      }
      Section("接続先") {
        ForEach(servers) { server in
          Button { editing = server } label: {
            HStack {
              Text(server.name)
              Spacer()
              Text(model.mcpConnectionIsReviewed(server) ? "確認済み" : "要確認")
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(minHeight: MemoraSpacing.touchTarget)
          }
          .contextMenu {
            Button("この端末から接続を削除", icon: .trash, role: .destructive) { model.deleteMCPServer(server.id) }
          }
        }
        Button(servers.isEmpty ? "トークンを登録" : "別の接続を追加", icon: .plus) { editing = preset.server() }
          .accessibilityIdentifier("connector.preset.add")
      }
    }
    .navigationTitle(preset.name)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { MCPServerEditor(server: $0) }
  }
}
