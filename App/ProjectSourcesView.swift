import SwiftUI

struct ProjectSourcesView: View {
  @Environment(MemoraModel.self) private var model
  var projectID: UUID?
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    let items = model.workspaceItems(projectID: projectID).filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    List {
      ForEach(items) { item in ProjectWorkspaceRow(item: item) }
    }
    .listStyle(.plain).scrollContentBackground(.hidden)
    .background(MemoraPalette.background)
    .navigationTitle("ソース").navigationBarTitleDisplayMode(.inline)
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "ソースを検索")
    .overlay {
      if items.isEmpty {
        ContentUnavailableView(query.isEmpty ? "ソースはまだありません" : "該当するソースはありません", icon: .doc)
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        ToolbarIconButton("検索", icon: .magnifyingglass) { isSearching = true }
      }
      if let projectID {
        ToolbarItem(placement: .topBarTrailing) {
          ToolbarIconButton("ソースを追加", icon: .plus) { model.sourceAddProjectID = projectID }
        }
      }
    }
    .hideBottomBarOnScroll(model.selectedTab.rawValue)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
  }
}
