import SwiftUI

struct FileCreationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var projectName = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("プロジェクト名") {
          TextField("例：新規アプリ", text: $projectName)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .onSubmit(createProject)
        }

        Section {
          Label("関連する議事録は、プロジェクトを作成した後に追加できます。", icon: .folder)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("プロジェクトを作成")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("作成", action: createProject)
            .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }

  private func createProject() {
    let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    model.addSpace(name: trimmed)
    model.fileSection = .projects
    model.selectedTab = .files
    dismiss()
  }
}
