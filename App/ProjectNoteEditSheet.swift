import SwiftUI

struct ProjectNoteEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var source: ProjectSource
  @State private var title: String
  @State private var text: String
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(source: ProjectSource, text: String) {
    self.source = source
    _title = State(initialValue: source.title)
    _text = State(initialValue: DraftStore.load("workspace.note.\(source.id)") ?? text)
  }

  var body: some View {
    NavigationStack {
      Form {
        if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        TextField("タイトル", text: $title)
        TextEditor(text: $text).frame(minHeight: 240).accessibilityLabel("メモ本文")
      }
      .onChange(of: text) { _, value in DraftStore.save(value, key: "workspace.note.\(source.id)") }
      .navigationTitle("メモを編集").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            isSaving = true
            Task {
              defer { isSaving = false }
              do {
                if try await model.updateProjectNote(source.id, title: title, text: text) {
                  DraftStore.clear("workspace.note.\(source.id)"); dismiss()
                }
                else { errorMessage = "保存できませんでした。開き直して確認してください。" }
              } catch { errorMessage = error.localizedDescription }
            }
          }.disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
