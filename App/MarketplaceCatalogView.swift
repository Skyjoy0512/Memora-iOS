import SwiftUI

struct MarketplaceCatalogView: View {
  var section: ToolsSection
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    ZStack {
      if isSearching && !CollectionSearch.hasQuery(query) {
        CollectionSearchState(title: "\(section.title)を検索", message: "名前や用途で検索")
      } else {
        switch section {
        case .skills: ToolsSkillsList(query: $query)
        case .templates: ToolsTemplatesList(query: $query)
        case .connectors: ToolsConnectorsList(query: $query)
        }
      }
    }
    .background(MemoraPalette.background)
    .navigationTitle(section.title)
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      MarketplaceSearchBar(query: $query, isSearching: $isSearching, prompt: "\(section.title)を検索")
    }
    .toolbar {
      ToolbarActionItem(usesSystemBackground: true) { MarketplaceCreationMenu(section: section) }
    }
  }
}
