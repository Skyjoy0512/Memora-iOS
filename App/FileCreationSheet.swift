import SwiftUI

struct FileCreationSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var projectName = ""
  @State private var mode = FileCreationMode.choose

  var body: some View {
    NavigationStack {
      Group {
        switch mode {
        case .choose:
          List {
            Button {
              dismiss()
              Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                model.isCaptureSourcePresented = true
              }
            } label: {
              creationRow(
                title: "議事録ファイル",
                subtitle: "録音するか、音声を読み込む",
                symbol: "doc.text"
              )
            }
            .buttonStyle(.plain)

            Button {
              withAnimation(MemoraMotion.screen) {
                mode = .project
              }
            } label: {
              creationRow(
                title: "プロジェクト",
                subtitle: "複数の議事録をまとめる",
                symbol: "folder"
              )
            }
            .buttonStyle(.plain)
          }
          .listStyle(.insetGrouped)
        case .project:
          Form {
            Section("プロジェクト名") {
              TextField("例：新規アプリ", text: $projectName)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(createProject)
            }
          }
        }
      }
      .navigationTitle(mode == .choose ? "新しく追加" : "プロジェクト")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(mode == .choose ? "閉じる" : "戻る") {
            if mode == .choose {
              dismiss()
            } else {
              withAnimation(MemoraMotion.screen) { mode = .choose }
            }
          }
        }
        if mode == .project {
          ToolbarItem(placement: .confirmationAction) {
            Button("作成", action: createProject)
              .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }

  private func creationRow(title: String, subtitle: String, symbol: String) -> some View {
    HStack(spacing: 14) {
      MemoraIconBadge(symbol: symbol, size: 40)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline).foregroundStyle(.primary)
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption.bold())
        .foregroundStyle(.tertiary)
    }
    .frame(minHeight: 62)
    .contentShape(Rectangle())
  }

  private func createProject() {
    let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    model.addSpace(name: trimmed)
    model.fileSection = .projects
    dismiss()
  }
}

private enum FileCreationMode {
  case choose
  case project
}
