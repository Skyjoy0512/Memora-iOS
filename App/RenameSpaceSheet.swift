import SwiftUI

/// Renames a project.
struct RenameSpaceSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var space: MemoraSpace
  @State private var name: String
  @State private var saveError = false
  @State private var confirmsDiscard = false
  @FocusState private var isFocused: Bool

  init(space: MemoraSpace) {
    self.space = space
    _name = State(initialValue: space.name)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        TextField("プロジェクト名", text: $name)
          .focused($isFocused)
          .submitLabel(.done)
          .onSubmit(save)
      }
      .navigationTitle("名前を変更")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) {
            isFocused = false
            if hasChanges { confirmsDiscard = true } else { dismiss() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark, action: save)
            .disabled(trimmedName.isEmpty || !hasChanges)
        }
      }
      .interactiveDismissDisabled(hasChanges)
      .task { isFocused = true }
      .alert("変更を破棄しますか？", isPresented: $confirmsDiscard) {
        Button("編集を続ける", role: .cancel) {}
        Button("変更を破棄", role: .destructive) { dismiss() }
      } message: { Text("保存前の名前の変更だけを破棄します。プロジェクト内の記録は変更しません。") }
      .alert("名前を変更できませんでした", isPresented: $saveError) {
        Button("閉じる", role: .cancel) {}
      } message: { Text("プロジェクトや保存先の状態を確認してください。入力した名前は画面に残っています。") }
    }
    .presentationDetents([.medium])
  }

  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var hasChanges: Bool { trimmedName != space.name.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func save() {
    guard !trimmedName.isEmpty, hasChanges else { return }
    isFocused = false
    if model.renameSpace(space.id, name: trimmedName) { dismiss() }
    else { saveError = true }
  }
}
