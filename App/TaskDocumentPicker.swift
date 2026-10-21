import SwiftUI

struct TaskDocumentPicker: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: [UUID]

  var body: some View {
    NavigationStack {
      MemoraList {
        ForEach(model.documents) { document in
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
        }
      }
      .navigationTitle("資料を添付")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
    }
  }
}
