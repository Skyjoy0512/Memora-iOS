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
    _title = State(initialValue: DraftStore.load("workspace.note.\(source.id).title") ?? source.title)
    _text = State(initialValue: DraftStore.load("workspace.note.\(source.id)") ?? text)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        TextField("タイトル", text: $title).accessibilityLabel("タイトル")
        TextEditor(text: $text).frame(minHeight: 240).accessibilityLabel("メモ本文")
        InlineLinkSummaryView(text: $text)
      }
      .disabled(isSaving)
      .onChange(of: title) { _, value in DraftStore.save(value, key: "workspace.note.\(source.id).title") }
      .onChange(of: text) { _, value in DraftStore.save(value, key: "workspace.note.\(source.id)") }
      .navigationTitle("メモを編集").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            isSaving = true
            Task {
              defer { isSaving = false }
              do {
                if try await model.updateProjectNote(source.id, title: title, text: text, presentsErrorsLocally: true) {
                  DraftStore.clear("workspace.note.\(source.id)")
                  DraftStore.clear("workspace.note.\(source.id).title")
                  dismiss()
                }
                else { errorMessage = "保存できませんでした。開き直して確認してください。" }
              } catch { errorMessage = error.localizedDescription }
            }
          }.disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .interactiveDismissDisabled(isSaving)
    }
  }
}
