import SwiftUI

struct MarketplaceInstalledView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var connectedIDs: Set<String> = []

  var body: some View {
    let services = IntegrationCatalog.services.filter { connectedIDs.contains($0.id) }.map(MarketplaceItem.service)
    let templates = model.installedMarketTemplates.map(MarketplaceItem.template)
    let skills = model.skillCatalog.filter { !model.disabledSkillIDs.contains($0.id) }.map(MarketplaceItem.skill)
    MarketplaceCatalogColumn {
      if !services.isEmpty {
        MarketplaceCardSection(title: "コネクタ", items: services, onConnectorDismiss: refreshConnections)
      }
      if !templates.isEmpty { MarketplaceCardSection(title: "要約テンプレート", items: templates) }
      if !skills.isEmpty { MarketplaceCardSection(title: "スキル", items: skills) }
      if services.isEmpty && templates.isEmpty && skills.isEmpty {
        ContentUnavailableView("利用中の項目はありません", icon: .bag)
      }
    }
    .navigationTitle("利用中")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: refreshConnections)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { refreshConnections() }
    }
  }

  private func refreshConnections() {
    connectedIDs = Set(IntegrationCatalog.services.filter { model.integrationHasConnection($0.id) }.map(\.id))
  }
}
