import SwiftUI

/// Takes the transcript iPhone wrote for a call, pasted from Notes, and makes
/// a call record from it.
struct CallTranscriptPasteView: View {
  @Environment(MemoraModel.self) private var model
  var onCreated: () -> Void
  @State private var title = ""
  @State private var transcript = ""
  @FocusState private var isEditorFocused: Bool

  var body: some View {
    Form {
      Section("タイトル") {
        TextField("例：○○さんとの通話", text: $title)
      }
      Section {
        TextEditor(text: $transcript)
          .frame(minHeight: 280)
          .focused($isEditorFocused)
      } header: {
        Text("文字起こし")
      } footer: {
        Text("「名前: 発言」の形の行は、話した人として残ります。")
      }
    }
    .navigationTitle("文字起こしを貼り付け")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        ToolbarIconButton("通話メモを作る", icon: .checkmark) {
          if model.createCallRecord(fromTranscript: transcript, title: title) != nil {
            onCreated()
          }
        }
        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .onAppear { isEditorFocused = true }
  }
}
