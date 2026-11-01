import Foundation

enum ProjectQuestionSourceFailure: LocalizedError {
  case unavailable(String)
  case cloudRestricted(UUID)

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason): reason
    case .cloudRestricted:
      "リンクは保存しました。外部AIへ送る場合は、資料のプライバシー設定で送信を許可してください。"
    }
  }
}
