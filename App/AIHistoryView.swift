import SwiftUI

struct AIHistoryView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var isSearching = false
  var entries: [AIConversationEntry]
  /// Asks the stored question again, as a separate choice from reading it.
  var ask: (String) -> Void
  var continueConversation: ((AIConversationEntry) -> Void)?
  var delete: (UUID) -> Void

  var body: some View {
    let filteredEntries = AIHistorySearch.matching(entries, query: query)
    NavigationStack {
      Group {
        if entries.isEmpty {
          ContentUnavailableView("まだ履歴がありません", icon: .clockArrowCirclepath)
        } else if filteredEntries.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          List {
            ForEach(filteredEntries) { entry in
              NavigationLink {
                AIHistoryDetailView(entry: entry, ask: ask, continueConversation: continueConversation)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.question)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                  Text("\(entry.scopeLabel) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
              }
            }
            .onDelete { indexSet in
              for index in indexSet where filteredEntries.indices.contains(index) {
                delete(filteredEntries[index].id)
              }
            }
          }
        }
      }
      .navigationTitle("質問履歴")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(isSearching ? .hidden : .visible, for: .navigationBar)
      .safeAreaInset(edge: .top, spacing: 0) {
        if isSearching {
          ToolbarSearchField(text: $query, isPresented: $isSearching, prompt: "質問・回答を検索")
        }
      }
      .toolbar {
        ToolbarActionItem {
          ToolbarIconButton("履歴を検索", icon: .magnifyingglass, artwork: .searchIntelligence) {
            isSearching = true
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
    }
  }
}
