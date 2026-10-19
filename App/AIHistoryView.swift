import SwiftUI

struct AIHistoryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var isSearching = false
  var entries: [AIConversationEntry]
  /// Asks the stored question again, as a separate choice from reading it.
  var ask: (String) -> Void
  var continueConversation: ((AIConversationEntry) -> Void)?
  var delete: (UUID) -> Void

  var body: some View {
    let scopedEntries = entries.filter { $0.episode?.workspaceID == model.currentTeamID && $0.episode?.personIDs.first == model.aiPersonScopeID }
    let filteredEntries = AIHistorySearch.matching(scopedEntries, query: query)
    let linkedIDs = Set(entries.compactMap(\.webResearchReportID))
    let legacyReports = model.webResearchReports.filter {
      $0.workspaceID == model.currentTeamID && !linkedIDs.contains($0.id) && (query.isEmpty || $0.query.localizedCaseInsensitiveContains(query) || $0.answer.localizedCaseInsensitiveContains(query))
    }
    NavigationStack {
      Group {
        if entries.isEmpty && model.webResearchReports.isEmpty {
          ContentUnavailableView("まだ履歴がありません", icon: .clockArrowCirclepath)
        } else if filteredEntries.isEmpty && legacyReports.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          List {
            ForEach(filteredEntries) { entry in
              NavigationLink {
                AIHistoryDetailView(entry: entry, ask: ask, continueConversation: continueConversation,
                  openProjectAction: { id in dismiss(); model.openProject(id) })
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
                .padding(.vertical, MemoraSpacing.xs)
              }
            }
            .onDelete { indexSet in
              for index in indexSet where filteredEntries.indices.contains(index) {
                delete(filteredEntries[index].id)
              }
            }
            if !legacyReports.isEmpty {
              Section("Web検索") {
                ForEach(legacyReports) { report in
                  NavigationLink {
                    WebResearchDetailView(reportID: report.id, openProjectAction: { id in dismiss(); model.openProject(id) })
                  } label: {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(report.query).font(.body.weight(.medium)).lineLimit(2)
                      Text(report.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                  }
                }
                .onDelete { offsets in for index in offsets where legacyReports.indices.contains(index) { _ = model.deleteWebResearch(legacyReports[index].id) } }
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
