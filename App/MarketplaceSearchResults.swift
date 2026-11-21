import SwiftUI

struct MarketplaceSearchResults: View {
  @Environment(MemoraModel.self) private var model
  @Binding var query: String

  var body: some View {
    let skills = model.skillCatalog.filter {
      ToolsCatalogSearch.matches(query, fields: $0.searchFields)
    }.map(MarketplaceItem.skill)
    let templates = (model.customTemplates + SummaryTemplateCatalog.market).filter {
      ToolsCatalogSearch.matches(query, fields: [$0.title, $0.detail, $0.category.title, $0.focus]
        + $0.sections + $0.occupationTags + $0.useCaseTags)
    }.map(MarketplaceItem.template)
    let services = IntegrationCatalog.services.filter {
      ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.aliases)
    }.map(MarketplaceItem.service)
    let groups = [(ToolsSection.skills.title, skills), (ToolsSection.templates.title, templates), (ToolsSection.connectors.title, services)]

    Group {
      if groups.allSatisfy({ $0.1.isEmpty }) {
        ToolsSearchEmptyState(scopeName: "すべてのカテゴリ") { query = "" }
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
