import Foundation

enum IntegrationConnectionError: LocalizedError {
  case backendNotConfigured
  var errorDescription: String? { "外部連携の認証済みサーバーが未接続のため実行できません。" }
}
