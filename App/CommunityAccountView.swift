import SwiftUI

struct CommunityAccountView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var session = FirebaseCommunitySession.shared
  @State private var email = ""
  @State private var password = ""
  @State private var createsAccount = false
  @State private var isWorking = false
  @State private var message: String?

  var body: some View {
    NavigationStack {
      MemoraForm {
        if !FirebaseMarketplaceClient.isConfigured {
          Section { Text(CommunityError.unconfigured.localizedDescription).foregroundStyle(.secondary) }
        } else if session.isSignedIn {
          Section {
            Label(session.email ?? "コミュニティアカウント", icon: .person)
            Button("メール確認を反映") {
              run { try await session.refreshVerification(); message = "確認状態を更新しました。" }
            }
            Button("ログアウト", role: .destructive) { run { try session.signOut(); message = nil } }
          }
          Section {
            Button("非表示にした投稿者をすべて戻す") { CommunityMarketplace.shared.unblockAll() }
          }
        } else {
          Section {
            Picker("アカウント", selection: $createsAccount) {
              Text("ログイン").tag(false); Text("新規登録").tag(true)
            }.pickerStyle(.segmented)
            TextField("メールアドレス", text: $email).textContentType(.username)
              .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("パスワード", text: $password).textContentType(createsAccount ? .newPassword : .password)
            Button(createsAccount ? "登録して確認メールを送る" : "ログイン") {
              run {
                try await session.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, create: createsAccount)
                password = ""
                if createsAccount { message = "確認メールのリンクを開き、「メール確認を反映」を押してください。" }
                else { dismiss() }
              }
            }.disabled(email.isEmpty || password.count < 8)
          }
        }
        if isWorking { Section { ProgressView() } }
        if let message { Section { Text(message).font(.subheadline) } }
      }
      .disabled(isWorking)
      .navigationTitle("コミュニティアカウント").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("閉じる", icon: .xmark) { dismiss() } } }
      .interactiveDismissDisabled(isWorking)
    }
  }

  private func run(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !isWorking else { return }; isWorking = true; message = nil
    Task { @MainActor in
      defer { isWorking = false }
      do { try await operation() } catch { message = error.localizedDescription }
    }
  }
}
