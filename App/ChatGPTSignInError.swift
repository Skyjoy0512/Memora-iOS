import Foundation

/// Why a ChatGPT sign-in could not complete.
enum ChatGPTSignInError: LocalizedError, Equatable {
  /// The person closed the sign-in page before it finished.
  case cancelled
  /// The sign-in page returned something the app could not use.
  case callbackFailed
  /// The sign-in page could not be opened.
  case browserUnavailable
  /// OpenAI did not register this app, so no client ID was issued.
  case registrationIncomplete
  /// The token endpoint answered with something the app could not use.
  case invalidResponse
  /// The service could not be reached.
  case serviceUnavailable
  /// The sign-in returned a different ChatGPT account than the saved one.
  case accountMismatch

  var errorDescription: String? {
    switch self {
    case .cancelled:
      return "ChatGPTのサインインは中止されました。"
    case .callbackFailed:
      return "ChatGPTからの応答を確認できませんでした。もう一度サインインしてください。"
    case .browserUnavailable:
      return "サインインページを開けませんでした。ブラウザの設定を確認してください。"
    case .registrationIncomplete:
      return "ChatGPTがアプリの登録を完了しませんでした。もう一度サインインしてください。"
    case .invalidResponse:
      return "認証サーバーの応答を利用できません。もう一度サインインしてください。"
    case .serviceUnavailable:
      return "ChatGPTに接続できませんでした。しばらくしてからもう一度お試しください。"
    case .accountMismatch:
      return "以前サインインしたChatGPTアカウントとは別のアカウントです。元のアカウントでサインインしてください。"
    }
  }
}
