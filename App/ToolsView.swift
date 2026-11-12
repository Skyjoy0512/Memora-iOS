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
        case .skills: ToolsSkillsList(query: $query)
        case .templates: ToolsTemplatesList(query: $query)
        case .connectors: ToolsConnectorsList(query: $query)
        }
      } else if isSearching {
        MarketplaceSearchResults(query: query)
      } else {
        MarketplaceHomeView()
      }
    }
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle(section?.title ?? "マーケットプレイス")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MemoraPalette.background, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      MarketplaceSearchBar(query: $query, isSearching: $isSearching,
        prompt: "\(section?.title ?? "マーケットプレイス")を検索")
    }
    .toolbar {
      ToolbarActionItem(placement: .topBarLeading) {
        ToolbarIconButton("メニュー", icon: .line3Horizontal) { onOpenSidebar() }
      }
      ToolbarItem(placement: .principal) {
        Menu {
          Picker("カタログ", selection: $scope) {
            ForEach(MarketplaceScope.allCases) { scope in
              Text(scope.title).tag(scope)
            }
          }
        } label: {
          HStack(spacing: MemoraSpacing.xs) {
            Text(section?.title ?? "マーケットプレイス").font(.headline)
            Image(icon: .chevronDown, size: 12)
              .foregroundStyle(MemoraPalette.textSecondary)
              .accessibilityHidden(true)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("カタログ、\(section?.title ?? "マーケットプレイス")")
        .accessibilityIdentifier("marketplace.scope")
      }
      ToolbarActionItem(usesSystemBackground: true) { MarketplaceCreationMenu(section: section) }
    }
    .onChange(of: scope) { _, _ in query = "" }
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
}
