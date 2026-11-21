import SwiftUI

struct ToolsTemplatesList: View {
  @Environment(MemoraModel.self) private var model
  @Binding var query: String
  var broadenSearch: (() -> Void)?

  var body: some View {
    let market = SummaryTemplateCatalog.market.filter(matches)
    let custom = model.customTemplates.filter(matches)
    let installed = market.filter { model.installedTemplateIDs.contains($0.id) }
    let categories = SummaryTemplateCategory.allCases.compactMap { category -> (SummaryTemplateCategory, [SummaryMarketTemplate])? in
      let templates = market.filter { $0.category == category && !model.installedTemplateIDs.contains($0.id) }
      return templates.isEmpty ? nil : (category, templates)
    }
    let badges = ["template:" + model.defaultSummaryChoice.id: "自動生成の既定"]
    MarketplaceCatalogColumn {
      if !custom.isEmpty || !installed.isEmpty {
        MarketplaceCardSection(title: "マイテンプレート", items: (custom + installed).map(MarketplaceItem.template), badges: badges)
      }
      ForEach(categories, id: \.0) { category, templates in
        MarketplaceCardSection(title: category.title, items: templates.map(MarketplaceItem.template), badges: badges)
      }
      if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        NavigationLink { SummaryTemplateMarketplaceView() } label: {
          Label("マイテンプレートを管理", icon: .sliderHorizontal3)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
      }
      if custom.isEmpty && installed.isEmpty && categories.isEmpty {
        ToolsSearchEmptyState(scopeName: ToolsSection.templates.title, broadenSearch: broadenSearch) { query = "" }
      }
    }
  }

  private func matches(_ template: SummaryMarketTemplate) -> Bool {
    ToolsCatalogSearch.matches(query, fields: [template.title, template.detail, template.category.title, template.focus]
      + template.sections + template.occupationTags + template.useCaseTags)
  }
}
