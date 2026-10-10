import SwiftUI

/// Renames a project.
struct RenameSpaceSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var space: MemoraSpace
  @State private var name: String

  init(space: MemoraSpace) {
    self.space = space
    _name = State(initialValue: space.name)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("プロジェクト名", text: $name)
      }
      .navigationTitle("名前を変更")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            if model.renameSpace(space.id, name: name) { dismiss() }
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
  }
}
