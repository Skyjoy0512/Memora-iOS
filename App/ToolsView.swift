import SwiftUI

// The saved Tools destination now opens the marketplace without replacing navigation state.
struct ToolsView: View {
  @Environment(MemoraModel.self) private var model
  var onOpenSidebar: () -> Void
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    Group {
      if isSearching {
        MarketplaceSearchResults(query: query)
      } else {
        MarketplaceHomeView()
      }
    }
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle("マーケットプレイス")
    .navigationBarTitleDisplayMode(.large)
    .toolbarBackground(MemoraPalette.background, for: .navigationBar)
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "マーケットプレイスを検索")
    .toolbar {
      ToolbarActionItem(placement: .topBarLeading) {
        ToolbarIconButton("メニュー", icon: .line3Horizontal) { onOpenSidebar() }
      }
      ToolbarActionItem {
        ToolbarIconButton("検索", icon: .magnifyingglass) { isSearching = true }
      }
      ToolbarActionItem(usesSystemBackground: true) { MarketplaceCreationMenu() }
    }
    .onChange(of: model.sidebarSearchRequest) { _, request in
      guard request != nil, model.isToolsPresented else { return }
      isSearching = true
    }
  }
}
