import Foundation

enum CallingError: LocalizedError {
  case notConfigured
  case invalidNumber
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "通話サービスはまだ接続されていません。通話にはMemoraの通話サーバー（Twilioなど）の設定が必要です。録音はこれまでどおり＋から使えます。"
    case .invalidNumber:
      "電話番号を確認してください。"
    case .verificationFailed:
      "番号を確認できませんでした。もう一度お試しください。"
    }
  }
}
