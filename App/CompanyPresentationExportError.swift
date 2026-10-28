import Foundation

enum CompanyPresentationExportError: LocalizedError {
  case unavailable, templateUnavailable, unsupported, historyLimit, missingPrevious, stale, save

  var errorDescription: String? {
    switch self {
    case .unavailable: String(localized: "この資料の保存先に書き込めません。ワークスペースと保存状態を確認してください。")
    case .templateUnavailable: String(localized: "関連する会社テンプレートが見つかりません。原本を確認してください。")
    case .unsupported: String(localized: "この資料は追加方式で再出力できません。構造化スライドと対応する会社PPTXが必要です。差し込み方式は会社テンプレート画面から生成してください。")
    case .historyLimit: String(localized: "以前のファイルが100件に達したため、書き出せません。履歴を自動削除することはありません。")
    case .missingPrevious: String(localized: "以前のファイルを保持できません。元のファイルを復元してから再試行してください。")
    case .stale: String(localized: "資料・会社書式・ワークスペースが変更されました。最新の内容を確認して再試行してください。")
    case .save: String(localized: "書き出したファイルを資料に保存できませんでした。前回のファイルと本文は変更していません。空き容量を確認して再試行してください。")
    }
  }
}
