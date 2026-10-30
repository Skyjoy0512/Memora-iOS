import SwiftUI

/// Edits a document's title and body. Slides are edited as an outline: `# `
/// starts a slide, `- ` adds a point and `> ` a speaker note.
struct DocumentEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var cancelsEditing = false
  @State private var editorCompleted = false
  var document: MemoraDocument
  @State private var title: String
  @State private var bodyText: String
  @State private var saveError = false
  @FocusState private var focusedField: Field?

  init(document: MemoraDocument) {
    self.document = document
    _title = State(initialValue: document.title)
    _bodyText = State(initialValue: document.kind == .slides
      ? DocumentSlide.outline(of: document.slides)
      : document.markdown)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section("タイトル") {
          TextField("タイトル", text: $title)
            .focused($focusedField, equals: .title)
            .submitLabel(.next)
            .onSubmit { focusedField = .body }
        }
        Section {
          TextEditor(text: $bodyText)
            .accessibilityLabel(document.kind == .slides ? "スライドのアウトライン" : "資料の本文")
            .focused($focusedField, equals: .body)
            .font(.body.monospaced())
            .frame(minHeight: 360)
        } header: {
          Text(document.kind == .slides ? "スライド" : "本文（Markdown）")
        } footer: {
          if document.companyTemplateID != nil {
            Text("ここでの編集は本文に保存されます。会社ファイルへの再差込は未対応のため、生成済みファイルは編集前のまま保持します。")
          }
          if document.kind == .slides {
            Text("「# 」で新しいスライド、「- 」で要点、「> 」で話すメモになります。")
          }
        }
      }
      .navigationTitle("\(document.kind.label)を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) {
            focusedField = nil
            cancelsEditing = true
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            focusedField = nil
            if model.updateDocument(document.id, title: title, body: bodyText, expectedUpdatedAt: document.updatedAt) { editorCompleted = true; dismiss() }
            else { saveError = true }
          }
          .disabled(!hasChanges)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完了") { focusedField = nil }
        }
      }
      .alert("保存できませんでした", isPresented: $saveError) {
        Button("閉じる", role: .cancel) {}
      } message: {
        Text("資料や保存先の状態を確認してください。入力内容はこの画面に残っています。")
      }
    }
    .protectsEditorDraft(key: "editor.\(model.currentTeamID ?? "personal").document.\(document.id).\(document.updatedAt.timeIntervalSince1970)",
      fields: [
        EditorDraftField("title", $title),
        EditorDraftField("body", $bodyText)
      ], cancels: $cancelsEditing, completed: editorCompleted)
  }

  private var hasChanges: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines) != document.title.trimmingCharacters(in: .whitespacesAndNewlines)
      || bodyText != (document.kind == .slides ? DocumentSlide.outline(of: document.slides) : document.markdown)
  }

  private enum Field: Hashable { case title, body }
}
