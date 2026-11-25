import Foundation

extension MemoraModel {
  /// The ChatGPT connection this device holds, when there is one.
  var chatGPTConnection: ChatGPTConnection? { ChatGPTCredentialStore.load() }

  /// Whether a ChatGPT account is connected.
  var isChatGPTSignedIn: Bool { chatGPTConnection != nil }

  /// Signs in with ChatGPT.
  ///
  /// The browser is opened by the coordinator; the person finishes there. The
  /// result is reported through `chatGPTSignInFailureMessage` and the
  /// account state.
  func signInWithChatGPT() async {
    guard FeatureFlags.isChatGPTSignInEnabled, !isChatGPTSigningIn else { return }
    isChatGPTSigningIn = true
    chatGPTSignInFailureMessage = nil
    defer { isChatGPTSigningIn = false }

    let coordinator = ChatGPTSignInCoordinator()
    switch await coordinator.signIn() {
    case .connected:
      chatGPTSignInFailureMessage = nil
    case .cancelled:
      chatGPTSignInFailureMessage = nil
    case .failed(let message):
      chatGPTSignInFailureMessage = message
    case .signedOut:
      chatGPTSignInFailureMessage = nil
    }
    account = chatGPTAccount()
  }

  /// Signs out of ChatGPT and removes the stored credentials.
  func signOutOfChatGPT() async {
    let coordinator = ChatGPTSignInCoordinator()
    switch await coordinator.signOut() {
    case .signedOut(let revoked):
      if account?.provider == .chatGPT { signOut() }
      chatGPTSignInFailureMessage = revoked ? nil
        : "このiPhoneの連携は解除しました。ChatGPT側の許可は、ChatGPTの設定から解除できます。"
    case .failed(let message):
      chatGPTSignInFailureMessage = message
    default:
      break
    }
  }

  /// The Memora account that mirrors the ChatGPT connection.
  ///
  /// ChatGPT sign-in is optional. Recording and organizing work without it,
  /// so the account only carries what ChatGPT told us.
  private func chatGPTAccount() -> MemoraAccount? {
    guard let connection = chatGPTConnection else { return nil }
    let displayName = connection.name?.isEmpty == false ? connection.name! : "ChatGPT"
    let email = connection.email?.isEmpty == false ? connection.email! : displayName
    return MemoraAccount(
      displayName: displayName,
      email: email,
      provider: .chatGPT,
      createdAt: account?.createdAt ?? .now
    )
  }
}
