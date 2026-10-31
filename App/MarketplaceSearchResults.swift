import SwiftUI

struct MarketplaceSearchResults: View {
  @Environment(MemoraModel.self) private var model
  var query: String

  var body: some View {
    let skills = model.skillCatalog.filter {
      ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.keywords)
    }.map(MarketplaceItem.skill)
    let templates = (model.customTemplates + SummaryTemplateCatalog.market).filter {
      ToolsCatalogSearch.matches(query, fields: [$0.title, $0.detail, $0.category.title, $0.focus]
        + $0.sections + $0.occupationTags + $0.useCaseTags)
    }.map(MarketplaceItem.template)
    let services = IntegrationCatalog.services.filter {
      ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.aliases)
    }.map(MarketplaceItem.service)
    let groups = [("スキル", skills), ("要約テンプレート", templates), ("連携", services)]

    Group {
      if !CollectionSearch.hasQuery(query) {
        CollectionSearchState(title: "マーケットプレイスを検索", message: "名前や用途で検索")
          .accessibilityIdentifier("tools.search.prompt")
      } else if groups.allSatisfy({ $0.1.isEmpty }) {
        ContentUnavailableView.search(text: query)
      } else {
        MarketplaceCatalogColumn {
          ForEach(groups, id: \.0) { title, items in
            if !items.isEmpty {
              MarketplaceCardSection(title: title, items: items)
            }
          }
        }
      }
    }
  }
}
