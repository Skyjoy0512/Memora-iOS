import Foundation

enum PDFSourcePartitionFailure: LocalizedError {
  case invalidFile
  case inputTooLarge
  case pageLimit
  case partLimit
  case aggregateLimit
  case singlePageTooLarge(Int)
  case encrypted
  case interactiveDocument
  case invalidPagesPerPart
  case writeFailed
  case originalChanged
  case stagingBusy
  case stagingLimit
  case insufficientCapacity

  var errorDescription: String? {
    switch self {
    case .invalidFile: "このPDFを読み込めませんでした。元のファイルは変更していません。"
    case .inputTooLarge: "分割できるPDFは500MB以下です。"
    case .pageLimit: "分割できるPDFは1〜10,000ページです。"
    case .partLimit: "分割結果が100ファイルを超えます。元のPDFの範囲を分けてお試しください。"
    case .aggregateLimit: "分割結果の合計が400MBを超えます。元のPDFの範囲を分けてお試しください。"
    case .singlePageTooLarge(let page): "元PDFの\(page)ページだけで50MBを超えるため、内容を保ったまま分割できません。"
    case .encrypted: "暗号化されたPDFは、その保護を保ったまま分割できません。権限のある保護されていないPDFを追加してください。"
    case .interactiveDocument: "入力フォームや電子署名を含むPDFは、その機能を保ったまま分割できません。元のPDFは変更していません。"
    case .invalidPagesPerPart: "分割するページ数は1〜10,000ページで指定してください。"
    case .writeFailed: "分割したPDFを保存できませんでした。保存容量を確認して再試行してください。"
    case .originalChanged: "分割中に元のPDFが変更されました。現在のファイルを確認して再試行してください。"
    case .stagingBusy: "別のPDFを準備しています。完了してからもう一度お試しください。"
    case .stagingLimit: "PDFの一時保存容量の上限に達しています。進行中の保存が終わってから再試行してください。"
    case .insufficientCapacity: "PDFを分割するための空き容量が不足しています。端末の空き容量を増やして再試行してください。"
    }
  }
}
