import SwiftUI

struct ToolsConnectorsList: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @Binding var query: String
  @State private var connectedIDs: Set<String> = []

  var body: some View {
    let services = IntegrationCatalog.services.filter {
      ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.aliases)
    }
    let groups: [(String, [IntegrationCatalog])] = [
      ("接続済み", services.filter { connectedIDs.contains($0.id) }),
      ("おすすめ", services.filter { $0.isImplemented && !connectedIDs.contains($0.id) }),
      ("準備中", services.filter { !$0.isImplemented })
    ]
    MarketplaceCatalogColumn {
      ForEach(groups, id: \.0) { title, services in
        if !services.isEmpty {
          MarketplaceCardSection(title: title, items: services.map(MarketplaceItem.service),
            onConnectorDismiss: refreshConnections)
        }
      }
      if services.isEmpty { ToolsSearchEmptyState { query = "" } }
      if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        NavigationLink { MCPServersView() } label: {
          Label("カスタムコネクタを追加", icon: .plus)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
        NavigationLink { WebhookSettingsView() } label: {
          Label("Webhook", icon: .paperplane)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
      }
    }
    .onAppear(perform: refreshConnections)
    .onChange(of: scenePhase) { _, phase in if phase == .active { refreshConnections() } }
  }

  private func refreshConnections() {
    connectedIDs = Set(IntegrationCatalog.services.filter { model.integrationHasConnection($0.id) }.map(\.id))
  }
}
