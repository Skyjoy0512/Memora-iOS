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
    guard let service = IntegrationCatalog.services.first(where: { $0.id == id }) else { return "利用不可" }
    return model.integrationState(service).label
  }
}
