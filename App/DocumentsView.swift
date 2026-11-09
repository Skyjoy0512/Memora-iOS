import SwiftUI

/// Every document and slide deck, newest first. Opened from the side menu.
struct DocumentsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.revealMemoraSidebar) private var revealSidebar
  @State private var pendingDeletion: MemoraDocument?
  @State private var isEmptyWeekNoticePresented = false
  @State private var operationError: String?
  @State private var query = ""
  @State private var isSearching = false
  private var isSidebarRoot: Bool { model.selectedTab == .library && model.libraryPath == [.documents] }

  var body: some View {
    let isAwaitingQuery = isSearching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let documents = isAwaitingQuery ? [] : model.documents.filter { document in
      CollectionSearch.matches(query, fields: [document.displayTitle, document.markdown,
        document.spaceID.flatMap { model.space(id: $0)?.name } ?? "",
        document.weekStart == nil ? document.kind.label : "週報"]
        + document.slides.flatMap { [$0.title, $0.notes] + $0.bullets })
    }

    MemoraList {
      Section {
        ForEach(documents) { document in
          NavigationLink(value: LibraryRoute.document(document.id)) {
            DocumentRow(document: document, spaceName: document.spaceID.flatMap { model.space(id: $0)?.name })
          }
          .swipeActions(edge: .trailing) {
            Button("削除", icon: .trash, role: .destructive) {
              pendingDeletion = document
            }
          }
        }
      } header: {
        if isSearching && !isAwaitingQuery && !documents.isEmpty {
          Text("\(documents.count)件の検索結果")
            .font(MemoraTypography.metadata)
            .textCase(nil)
        }
      }
    }
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .overlay(alignment: .top) {
      if isSearching && documents.isEmpty {
        CollectionSearchState(title: isAwaitingQuery ? "資料を検索" : "見つかりません",
          message: isAwaitingQuery ? "タイトル・本文・プロジェクト名から探せます。" : "タイトルや本文の一部で検索してください。",
          clear: isAwaitingQuery ? nil : { query = "" })
          .accessibilityIdentifier("documents.search.state")
      } else if model.documents.isEmpty {
        ScrollView {
          MemoraEmptyState(icon: .docRichtext, title: "資料はまだありません",
            message: "AIに頼んで、記録から資料を作れます。",
            actionTitle: "AIで資料を作る", actionIcon: .sparkles) { model.openSystemDestination(.askAI) }
            .padding(.top, MemoraSpacing.section)
            .padding(.bottom, model.bottomContentClearance)
        }
      }
    }
    .navigationTitle("資料")
    .navigationBarBackButtonHidden(isSidebarRoot)
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "タイトル・本文を検索")
    .toolbar {
      if isSidebarRoot, let revealSidebar {
        ToolbarActionItem(placement: .topBarLeading) {
          ToolbarIconButton("メニュー", icon: .line3Horizontal, action: revealSidebar.callAsFunction)
        }
      }
      ToolbarActionItem {
        ToolbarIconButton("資料を検索", icon: .magnifyingglass) { isSearching = true }
      }
      ToolbarActionGap()
      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          Button("今週の週報を作る", icon: .calendarBadgeCheckmark) {
            switch model.makeWeeklyReview(containing: .now) {
            case .saved(let review):
              model.libraryPath.append(.document(review.id))
            case .noContent:
              isEmptyWeekNoticePresented = true
            case .failed:
              operationError = "週報を保存できませんでした。保存先を確認して、もう一度お試しください。"
            }
          }
          NavigationLink { MailDraftsView() } label: { Label("メール下書き", icon: .envelope) }
          NavigationLink { CompanyTemplatesView() } label: { Label("会社テンプレート", icon: .docOnDoc) }
        } label: { ToolbarActionLabel("資料の操作", icon: .ellipsis) }
      }
    }
    .onChange(of: model.sidebarSearchRequest) { _, request in
      if request != nil && isSidebarRoot && !model.isToolsPresented { isSearching = true }
    }
    .alert("今週はまだ記録がありません", isPresented: $isEmptyWeekNoticePresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("会議やジャーナルの記録、完了したタスクがあると、週報を作れます。")
    }
    .confirmationDialog(
      "「\(pendingDeletion?.displayTitle ?? "")」を削除しますか？",
      isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
      titleVisibility: .visible
    ) {
      Button("削除", role: .destructive) {
        if let document = pendingDeletion {
          if !model.deleteDocument(document.id) {
            operationError = "「\(document.displayTitle)」を削除できませんでした。資料は残っています。もう一度お試しください。"
          }
        }
        pendingDeletion = nil
      }
      Button("キャンセル", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text(pendingDeletion?.artifactHistory?.isEmpty == false
        ? "以前のファイルも削除され、元に戻せません。会社テンプレートの原本は残ります。"
        : "削除した資料は元に戻せません。")
    }
    .alert("操作を完了できませんでした", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
      Button("OK", role: .cancel) { operationError = nil }
    } message: { Text(operationError ?? "") }
  }
}
