import SwiftUI

struct IntegrationsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""

  var body: some View {
    let services = IntegrationCatalog.services.filter {
      query.isEmpty || ([$0.name, $0.summary] + $0.aliases + $0.toolNames).contains { $0.localizedStandardContains(query) }
    }
    List {
      Section {
        ForEach(services) { service in
          NavigationLink {
            IntegrationDetailView(service: service)
          } label: {
            SettingsValue(title: service.name,
              value: service.isImplemented ? status(service.id) : "未対応",
              icon: AIPluginIcon.resolve(pluginID: "service:" + service.id, name: service.name).systemSymbol)
          }
        }
      } header: {
        Text("サービス")
      } footer: {
        Text("外部の情報も、現在選択しているAIで処理します。新しい接続先には自動接続しません。")
      }
      Section("自動化とシステム") {
        NavigationLink { WebhookSettingsView() } label: { SettingsLabel("Webhook", icon: .paperplane) }
        NavigationLink { IOSIntegrationSettingsView() } label: {
          SettingsLabel("ウィジェットとショートカット", icon: .rectangleStack)
        }
      }
    }
    .searchable(text: $query, prompt: "サービスを検索")
    .memoraSettingsPage("連携")
  }

  private func status(_ id: String) -> String {
    guard let service = IntegrationCatalog.services.first(where: { $0.id == id }) else { return "利用不可" }
    return model.integrationState(service).label
  }
}
