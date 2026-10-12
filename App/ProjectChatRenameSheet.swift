import SwiftUI

struct ProjectChatRenameSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var thread: ProjectChatThread
  @State private var title: String

  init(thread: ProjectChatThread) {
    self.thread = thread
    _title = State(initialValue: thread.title)
  }

  var body: some View {
    NavigationStack {
      Form { TextField("チャット名", text: $title) }
        .navigationTitle("名前を変更").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            ToolbarIconButton("保存", icon: .checkmark) {
              if model.renameProjectChat(thread.id, title: title) { dismiss() }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
    }
  }
}
