import Foundation

enum GmailError: LocalizedError {
  /// The build has no Google OAuth client ID yet.
  case notConfigured
  case notConnected
  case cancelled
  case authorizationFailed
  /// Google refused the request; the message is Google's own.
  case server(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "Gmail連携にはGoogleのOAuthクライアントIDの設定が必要です。まだこのビルドには設定されていません。"
    case .notConnected:
      "Gmailが連携されていません。設定の「Gmail」から連携してください。"
    case .cancelled:
      "連携を取りやめました。"
    case .authorizationFailed:
      "Googleの認証に失敗しました。もう一度お試しください。"
    case .server(let message):
      "Gmailから読み込めませんでした。\(message)"
    }
  }
}
