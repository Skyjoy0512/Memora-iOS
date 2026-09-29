import SwiftUI

/// Every document and slide deck, newest first. Opened from the side menu.
struct DocumentsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var pendingDeletion: MemoraDocument?

  var body: some View {
    let documents = model.documents

    List {
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
    .listStyle(.plain)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .overlay {
      if documents.isEmpty {
        ContentUnavailableView(
          "資料はまだありません",
          icon: .docRichtext,
          description: Text("Ask AIをエージェントにして「会議から資料を作って」と頼むと、ここに保存されます。")
        )
      }
    }
    .navigationTitle("資料")
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
      Text("削除した資料は元に戻せません。")
    }
  }
}
