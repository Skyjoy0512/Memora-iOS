import SwiftUI

struct ProjectSourcesView: View {
  @Environment(MemoraModel.self) private var model
  var projectID: UUID?
  var zoomNamespace: Namespace.ID?
  @State private var query = ""
  @State private var isSearching = false
  @State private var matchingSourceIDs: Set<UUID> = []
  @State private var completedQuery = ""

  var body: some View {
    let items = model.workspaceItems(projectID: projectID).filter { item in
      if !CollectionSearch.hasQuery(query) { return true }
      switch item {
      case .source(let source):
        return CollectionSearch.matches(query, fields: [source.title, source.summary ?? ""]) ||
          (completedQuery == query && matchingSourceIDs.contains(source.id))
      case .recording(let record): return CollectionSearch.matches(query, fields: [model.searchText(for: record)])
      case .document(let document): return CollectionSearch.matches(query, fields: [document.displayTitle, document.plainText])
      }
    }
    List {
      ForEach(items) { item in
        ProjectWorkspaceRow(item: item, zoomNamespace: zoomNamespace)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 8, leading: ProjectLayout.horizontalInset,
            bottom: 8, trailing: ProjectLayout.horizontalInset))
      }
    }
    .listStyle(.plain).scrollContentBackground(.hidden)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .background(MemoraPalette.background)
    .navigationTitle("参考資料").navigationBarTitleDisplayMode(.inline)
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "参考資料を検索")
    .task(id: SourceSearchRequest(query: query, sources: model.projectSources, workspaceGeneration: model.aiWorkspaceGeneration)) {
      matchingSourceIDs = []
      let value = query
      guard CollectionSearch.hasQuery(value) else { completedQuery = value; return }
      let matches = await model.matchingSourceIDs(query: value, projectID: projectID, scoped: projectID != nil)
      guard !Task.isCancelled, query == value else { return }
      matchingSourceIDs = matches; completedQuery = value
    }
    .overlay {
      if items.isEmpty {
        if CollectionSearch.hasQuery(query), completedQuery != query {
          ProgressView("検索しています")
        } else {
          ContentUnavailableView(query.isEmpty ? "参考資料はまだありません" : "見つかりません", icon: .doc)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        ToolbarIconButton("検索", icon: .magnifyingglass) { isSearching = true }
      }
      ToolbarItem(placement: .topBarTrailing) {
        ToolbarIconButton("参考資料を追加", icon: .paperclip) {
          model.sourceAddProjectID = projectID
          model.isSourceAddPresented = true
        }
      }
    }
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
  }
}
