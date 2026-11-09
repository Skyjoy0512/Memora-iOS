import SwiftUI

struct TaskDocumentPicker: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: [UUID]
  @State private var query = ""

  var body: some View {
    let matches = model.documents.filter { CollectionSearch.matches(query, fields: [$0.displayTitle, $0.markdown]
      + $0.slides.flatMap { [$0.title, $0.notes] + $0.bullets }) }
    NavigationStack {
      MemoraList {
        ForEach(matches) { document in
          Toggle(document.displayTitle, isOn: Binding {
            selection.contains(document.id)
          } set: { selected in
            selection.removeAll { $0 == document.id }
            if selected { selection.append(document.id) }
          })
        }
      }
      .overlay {
        if model.documents.isEmpty {
          ContentUnavailableView("資料はありません", icon: .docText, description: Text("資料を作成・保存すると、課題に添付できます。"))
        } else if matches.isEmpty {
          ContentUnavailableView("見つかりません", icon: .magnifyingglass,
            description: Text("資料名や本文の一部で検索してください。"))
        }
      }
      .searchable(text: $query, prompt: "資料を検索")
      .navigationTitle("資料を添付")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
    }
  }
}
