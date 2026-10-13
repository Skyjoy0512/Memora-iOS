import Foundation

enum ExternalToolFailure: LocalizedError {
  case authenticationExpired, permissionDenied, rateLimited, unavailable, failed

  static func http(_ code: Int) -> Self {
    switch code { case 401: .authenticationExpired; case 403: .permissionDenied; case 429: .rateLimited; case 404: .unavailable; default: .failed }
  }
  var errorDescription: String? {
    switch self {
    case .authenticationExpired: "認証が期限切れか無効です。連携設定から再認証してください。"
    case .permissionDenied: "必要な権限がありません。連携設定とサービス側のアクセス権を確認してください。"
    case .rateLimited: "サービスのAPI利用上限に達しました。時間をおいて利用枠を確認してから再度依頼してください。自動再実行はしていません。"
    case .unavailable: "このツールまたは対象は現在利用できません。接続設定を確認してください。"
    case .failed: "外部サービスの操作に失敗しました。接続状態を確認してから再度依頼してください。自動再実行はしていません。"
    }
  }
  static func message(for error: any Error) -> String {
    if let failure = error as? Self { return failure.localizedDescription }
    if let failure = error as? MCPClientError {
      switch failure {
      case .invalidURL, .unauthorized, .malformed, .timeout: return failure.localizedDescription
      case .server: return Self.failed.localizedDescription
      }
    }
    if let failure = error as? GmailError {
      switch failure {
      case .notConnected, .notConfigured, .cancelled, .authorizationFailed: return failure.localizedDescription
      case .server: return Self.failed.localizedDescription
      }
    }
    return Self.failed.localizedDescription
  }
}
