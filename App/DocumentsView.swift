import SwiftUI

/// Every document and slide deck, newest first. Opened from the side menu.
struct DocumentsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var pendingDeletion: MemoraDocument?
  @State private var isEmptyWeekNoticePresented = false
  @State private var query = ""
  @State private var isSearching = false

  var body: some View {
    let isAwaitingQuery = isSearching && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let documents = isAwaitingQuery ? [] : model.documents.filter { document in
      CollectionSearch.matches(query, fields: [document.displayTitle, document.markdown,
        document.spaceID.flatMap { model.space(id: $0)?.name } ?? "",
        document.weekStart == nil ? document.kind.label : "週報"]
        + document.slides.flatMap { [$0.title, $0.notes] + $0.bullets })
    }

    MemoraList {
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
    }
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .overlay(alignment: .top) {
      if isSearching && documents.isEmpty {
        CollectionSearchState(title: isAwaitingQuery ? "資料を検索" : "見つかりません",
          message: isAwaitingQuery ? "タイトル・本文・プロジェクト名から探せます。" : "タイトルや本文の一部で検索してください。")
          .accessibilityIdentifier("documents.search.state")
      } else if model.documents.isEmpty {
        ScrollView {
          MemoraEmptyState(icon: .docRichtext, title: "資料はまだありません",
            message: "Ask AIに作成を頼んだ資料や、記録からまとめた週報がここに保存されます。",
            actionTitle: "Ask AIを開く", actionIcon: .sparkles) { model.openSystemDestination(.askAI) }
            .padding(.top, MemoraSpacing.section)
            .padding(.bottom, model.bottomContentClearance)
        }
      }
    }
    .navigationTitle("資料")
    .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "タイトル・本文を検索")
    .toolbar {
      ToolbarActionItem {
        ToolbarIconButton("資料を検索", icon: .magnifyingglass) { isSearching = true }
      }
      ToolbarActionGap()
      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          Button("今週の週報を作る", icon: .calendarBadgeCheckmark) {
            if let review = model.makeWeeklyReview(containing: .now) {
              model.libraryPath.append(.document(review.id))
            } else {
              isEmptyWeekNoticePresented = true
            }
          }
          NavigationLink { MailDraftsView() } label: { Label("メール下書き", icon: .envelope) }
          NavigationLink { CompanyTemplatesView() } label: { Label("会社テンプレート", icon: .docOnDoc) }
        } label: { ToolbarActionLabel("資料の操作", icon: .ellipsis) }
      }
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
          model.deleteDocument(document.id)
        }
        pendingDeletion = nil
      }
      Button("キャンセル", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text(pendingDeletion?.artifactHistory?.isEmpty == false
        ? "以前のファイルも削除され、元に戻せません。会社テンプレートの原本は残ります。"
        : "削除した資料は元に戻せません。")
    }
  }
}
