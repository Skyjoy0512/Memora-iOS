import Foundation

enum MCPOAuthError: LocalizedError {
  case configuration, callback, cancelled, tokenResponse, storage, reauthentication
  var errorDescription: String? {
    switch self {
    case .configuration: "公開Client ID、同じホストのHTTPS認可・トークンURL、要求する権限を確認してください。"
    case .callback: "認証の戻り先を確認できませんでした。もう一度サインインしてください。"
    case .cancelled: "サインインを取りやめました。"
    case .tokenResponse: "認証サーバーの応答を利用できません。権限・有効期限・公開クライアント対応を確認してください。"
    case .storage: "認証情報を安全に保存できませんでした。接続は完了していません。"
    case .reauthentication: "認証が必要です。MCPの接続設定からサインインしてください。操作は自動再送していません。"
    }
  }
}
