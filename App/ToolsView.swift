import SwiftUI

struct ToolsView: View {
  @Environment(MemoraModel.self) private var model
  var onOpenSidebar: () -> Void
  @State private var query = ""
  @State private var isSearching = false
  @State private var scope = MarketplaceScope.all

  var body: some View {
    let section = scope.section
    ZStack {
      if isSearching && !CollectionSearch.hasQuery(query) {
        CollectionSearchState(title: "\(section?.title ?? "マーケットプレイス")を検索", message: "名前や用途で検索")
          .accessibilityIdentifier("tools.search.prompt")
      } else if let section {
        switch section {
        case .skills: ToolsSkillsList(query: $query, broadenSearch: broadenSearch)
        case .templates: ToolsTemplatesList(query: $query, broadenSearch: broadenSearch)
        case .connectors: ToolsConnectorsList(query: $query, broadenSearch: broadenSearch)
        }
      } else if isSearching {
        MarketplaceSearchResults(query: $query)
      } else {
        MarketplaceHomeView()
      }
    }
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle(section?.title ?? "マーケットプレイス")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MemoraPalette.background, for: .navigationBar)
    .safeAreaInset(edge: .top, spacing: 0) {
      MemoraTextTabBar(items: MarketplaceScope.allCases, selection: $scope) { $0.shortTitle }
        .padding(.vertical, MemoraSpacing.sm)
        .background(MemoraPalette.background)
        .accessibilityIdentifier("marketplace.scope")
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      MarketplaceSearchBar(query: $query, isSearching: $isSearching,
        prompt: "\(section?.title ?? "マーケットプレイス")を検索")
    }
    .toolbar {
      ToolbarActionItem(placement: .topBarLeading) {
        ToolbarIconButton("メニュー", icon: .line3Horizontal) { onOpenSidebar() }
      }
      ToolbarActionItem(usesSystemBackground: true) { MarketplaceCreationMenu(section: section) }
    }
    .onChange(of: isSearching) { _, active in model.isSearchActive = active }
    .onChange(of: model.isSearchActive) { _, active in
      if !active { isSearching = false; query = "" }
    }
    .onChange(of: model.sidebarSearchRequest) { _, request in
      guard request != nil, model.isToolsPresented else { return }
      isSearching = true
    }
    .onDisappear { model.isSearchActive = false }
  }

  private func broadenSearch() { scope = .all }
}
