import Foundation

enum SourceMediaFailure: LocalizedError {
  case capacity, stagingLimit, invalidTemporaryFile, exportTooLarge

  var errorDescription: String? {
    switch self {
    case .capacity: "音声の準備に使う空き容量が不足しています。空き容量を増やして再試行してください。原本は保存されています。"
    case .stagingLimit: "音声の準備用データが上限に達しています。処理の完了後、時間をおいて再試行してください。原本は保存されています。"
    case .invalidTemporaryFile: "音声の準備用ファイルを確認できませんでした。再試行してください。原本は保存されています。"
    case .exportTooLarge: "変換後の音声が解析上限（100MB）を超えました。音声を短く分けて追加してください。原本は保存されています。"
    }
  }
}
