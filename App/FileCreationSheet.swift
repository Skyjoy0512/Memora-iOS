import SwiftUI

struct FileCreationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var projectName = ""
  @FocusState private var isNameFocused: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section("プロジェクト名") {
          TextField("例：新規アプリ", text: $projectName)
            .focused($isNameFocused)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .onSubmit(createProject)
        }

        Section {
          Label("作成後に録音したり、ライブラリの記録を追加したりできます。", icon: .folder)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("プロジェクトを作成")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("作成", icon: .plus, action: createProject)
            .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .task { isNameFocused = true }
    .presentationDragIndicator(.visible)
  }

  private func createProject() {
    let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let id = model.addSpace(name: trimmed) else { return }
    model.openProject(id)
    dismiss()
  }
}
