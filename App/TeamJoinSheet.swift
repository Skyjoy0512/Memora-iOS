import SwiftUI

/// Joins a team with the invite code a member sent.
struct TeamJoinSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var code = ""
  @State private var isWorking = false
  @State private var errorMessage: String?
  @FocusState private var isCodeFocused: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("招待コード", text: $code)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($isCodeFocused)
            .submitLabel(.join)
            .onSubmit(join)
        } footer: {
          Text("チームのメンバーから届いた招待コードを入力します。参加すると、チームのファイルをこの端末でも見て編集できます。")
        }

        if let errorMessage {
          Section {
            Label(errorMessage, icon: .exclamationmarkTriangle)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("チームに参加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isWorking {
            ProgressView()
          } else {
            Button("参加", action: join)
              .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      }
      .onAppear { isCodeFocused = true }
    }
  }

  private func join() {
    guard !isWorking else { return }
    isWorking = true
    errorMessage = nil
    Task {
      do {
        try await model.joinTeam(inviteCode: code)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isWorking = false
    }
  }
}
