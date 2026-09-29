import SwiftUI

/// Edits a document's title and body. Slides are edited as an outline: `# `
/// starts a slide, `- ` adds a point and `> ` a speaker note.
struct DocumentEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var document: MemoraDocument
  @State private var title: String
  @State private var bodyText: String

  init(document: MemoraDocument) {
    self.document = document
    _title = State(initialValue: document.title)
    _bodyText = State(initialValue: document.kind == .slides
      ? DocumentSlide.outline(of: document.slides)
      : document.markdown)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("タイトル") {
          TextField("タイトル", text: $title)
        }
        Section {
          TextEditor(text: $bodyText)
            .font(.body.monospaced())
            .frame(minHeight: 360)
        } header: {
          Text(document.kind == .slides ? "スライド" : "本文（Markdown）")
        } footer: {
          if document.kind == .slides {
            Text("「# 」で新しいスライド、「- 」で要点、「> 」で話すメモになります。")
          }
        }
      }
      .navigationTitle("\(document.kind.label)を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            model.updateDocument(document.id, title: title, body: bodyText)
            dismiss()
          }
        }
      }
    }
  }
}
