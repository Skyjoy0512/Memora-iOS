import SwiftUI

struct IntegrationsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""

  var body: some View {
    let services = IntegrationCatalog.services.filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
    }
    List {
      Section {
        ForEach(services) { service in
          NavigationLink {
            IntegrationDetailView(service: service)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(service.name)
              Text(service.isImplemented ? status(service.id) : "未対応")
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }
        }
      } footer: {
        Text("外部の情報も、現在選択しているAIで処理します。新しい接続先には自動接続しません。")
      }
      Section {
        NavigationLink("スキル") { SkillsView() }
      }
    }
    .searchable(text: $query, prompt: "サービスを検索")
    .navigationTitle("連携サービス")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func status(_ id: String) -> String {
    if !model.integrationIsEnabled(id) { return "Ask AIでは無効" }
    switch id {
    case "gmail": return GmailService.shared.isConnected ? "認証情報あり" : "未接続"
    case "notion": return NotionService.isConfigured ? "設定済み" : "未設定"
    case "mcp": return model.mcpServers.isEmpty ? "未設定" : "接続先 \(model.mcpServers.count)件"
    default: return "登録時にアクセス権を確認"
    }
  }
}
