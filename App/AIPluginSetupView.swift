import SwiftUI

struct AIPluginSetupView: View {
  @Environment(MemoraModel.self) private var model
  var plugin: AIPlugin

  var body: some View {
    if let service = IntegrationCatalog.services.first(where: { $0.id == plugin.serviceID }) {
      IntegrationDetailView(service: service)
    } else {
      Form {
        Section {
          Text(plugin.summary)
          Text(plugin.state.reason ?? "利用可能です。")
        }
        if plugin.id.hasPrefix("skill:") {
          NavigationLink("スキルを設定") { SkillsView() }
        } else if plugin.id.hasPrefix("tool:") {
          NavigationLink("Web検索を設定") { WebResearchSettingsView() }
        }
      }
      .navigationTitle(plugin.name)
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
