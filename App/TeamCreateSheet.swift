import SwiftUI

/// Names a new team. Its records are kept in the cloud and every member can
/// see and edit them; the personal workspace is untouched.
struct TeamCreateSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var isWorking = false
  @State private var errorMessage: String?
  @FocusState private var isNameFocused: Bool

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          TextField("チーム名", text: $name)
            .focused($isNameFocused)
            .submitLabel(.done)
            .onSubmit(create)
        } footer: {
          Text("チームのファイルはクラウドに保存され、メンバー全員が同じものを見て編集できます。個人のファイルはこの端末に残り、チームには入りません。")
        }

        if let errorMessage {
          Section {
            Label(errorMessage, icon: .exclamationmarkTriangle)
              .foregroundStyle(.secondary)
            if !model.hasTeamPlan {
              Button("プランを見る") {
                dismiss()
                model.isPaywallPresented = true
              }
            }
          }
        }
      }
      .navigationTitle("チームを作成")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isWorking {
            ProgressView()
          } else {
            Button("作成", action: create)
              .disabled(trimmedName.isEmpty)
          }
        }
      }
      .onAppear { isNameFocused = true }
    }
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func create() {
    guard !trimmedName.isEmpty, !isWorking else { return }
    isWorking = true
    errorMessage = nil
    Task {
      do {
        try await model.createTeam(named: trimmedName)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isWorking = false
    }
  }
}
