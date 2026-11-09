import SwiftUI

struct ProjectNoteEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var source: ProjectSource
  @State private var title: String
  @State private var text: String
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var context: LocalImportContext?
  @State private var isDraftReady = false
  private var draftKey: String { "workspace.note.\(source.id)" }

  init(source: ProjectSource, text: String) {
    self.source = source
    _title = State(initialValue: source.title)
    _text = State(initialValue: text)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        Group {
          TextField("タイトル", text: $title).accessibilityLabel("タイトル")
          TextEditor(text: $text).frame(minHeight: 240).accessibilityLabel("メモ本文")
          InlineLinkSummaryView(text: $text)
        }.disabled(!isDraftReady || context?.isCurrent(in: model) != true)
      }
      .disabled(isSaving)
      .onAppear {
        guard !isDraftReady else { return }
        do {
          let values = try DraftStore.readAll([draftKey, draftKey + ".title"])
          context = LocalImportContext(projectID: source.projectID, in: model)
          title = values[draftKey + ".title"] ?? title
          text = values[draftKey] ?? text
          isDraftReady = true
        } catch { errorMessage = error.localizedDescription }
      }
      .onChange(of: title) { _, value in
        if isDraftReady, context?.isCurrent(in: model) == true { DraftStore.save(value, key: draftKey + ".title") }
      }
      .onChange(of: text) { _, value in
        if isDraftReady, context?.isCurrent(in: model) == true { DraftStore.save(value, key: draftKey) }
      }
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
                guard context?.isCurrent(in: model) == true else {
                  errorMessage = "保存先が変更されました。開き直して確認してください。"
                  return
                }
                if try await model.updateProjectNote(source.id, title: title, text: text, presentsErrorsLocally: true,
                  expectedSource: source, removing: [draftKey, draftKey + ".title"].map { DraftStore.storageKey(for: $0) }) {
                  dismiss()
                }
                else { errorMessage = "保存できませんでした。開き直して確認してください。" }
              } catch { errorMessage = error.localizedDescription }
            }
          }.disabled(isSaving || !isDraftReady || context?.isCurrent(in: model) != true || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .interactiveDismissDisabled(isSaving)
    }
  }
}
