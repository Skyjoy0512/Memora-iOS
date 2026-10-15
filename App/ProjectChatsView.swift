import SwiftUI

struct ProjectChatsView: View {
  @Environment(MemoraModel.self) private var model
  var projectID: UUID?
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    let threads = model.projectChats.filter {
      (projectID == nil || $0.projectID == projectID) && (query.isEmpty || $0.title.localizedStandardContains(query))
    }.sorted { $0.updatedAt > $1.updatedAt }
    List { ForEach(threads) { thread in ProjectChatRow(thread: thread) } }
      .listStyle(.plain).scrollContentBackground(.hidden).background(MemoraPalette.background)
      .navigationTitle("チャット").navigationBarTitleDisplayMode(.inline)
      .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "チャットを検索")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { ToolbarIconButton("検索", icon: .magnifyingglass) { isSearching = true } }
        if let projectID {
          ToolbarItem(placement: .topBarTrailing) {
            ToolbarIconButton("新しいチャット", icon: .squareAndPencil) {
              if let id = model.createProjectChat(projectID: projectID) { model.openProjectChat(id) }
            }
          }
        }
      }
      .overlay { if threads.isEmpty { ContentUnavailableView("チャットはまだありません", icon: .chatBubble) } }
      .hideBottomBarOnScroll(model.selectedTab.rawValue)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
  }
}
