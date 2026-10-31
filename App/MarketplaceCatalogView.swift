import SwiftUI

struct MarketplaceCatalogView: View {
  var section: ToolsSection
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    Group {
      switch section {
      case .skills: ToolsSkillsList(query: $query)
      case .templates: ToolsTemplatesList(query: $query)
      case .connectors: ToolsConnectorsList(query: $query)
      }
    }
    .background(MemoraPalette.background)
    .navigationTitle(section.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "\(section.title)を検索")
    .toolbar {
      ToolbarActionItem {
        ToolbarIconButton("検索", icon: .magnifyingglass) { isSearching = true }
      }
      ToolbarActionItem(usesSystemBackground: true) { MarketplaceCreationMenu(section: section) }
    }
  }
}
