import Foundation

enum SourceMediaFailure: LocalizedError {
  case capacity, stagingLimit, invalidTemporaryFile, exportTooLarge
  case invalidDuration, invalidTranscript, transcriptTooLarge
  case thermalDeferred
  /// The silent parts of the recording could not be removed.
  case trimmingFailed

  var errorDescription: String? {
    switch self {
    case .capacity: "音声の準備に使う空き容量が不足しています。空き容量を増やして再試行してください。原本は保存されています。"
    case .stagingLimit: "音声の準備用データが上限に達しています。処理の完了後、時間をおいて再試行してください。原本は保存されています。"
    case .invalidTemporaryFile: "音声の準備用ファイルを確認できませんでした。再試行してください。原本は保存されています。"
    case .exportTooLarge: "変換後の音声が解析上限（100MB）を超えました。音声を短く分けて追加してください。原本は保存されています。"
    case .invalidDuration: "この音声を解析できません。24時間以内の再生可能なファイルを追加してください。原本は保存されています。"
    case .invalidTranscript: "文字起こしの時刻を確認できませんでした。原本は保存されています。もう一度お試しください。"
    case .transcriptTooLarge: "文字起こしが保存できる本文量を超えました。音声を短く分けて追加してください。原本は保存されています。"
    case .trimmingFailed: "無音部分の除去に失敗しました。元の音声で文字起こしを続行します。原本は保存されています。"
    case .thermalDeferred: "端末の温度が高いため音声の解析を保留しました。温度が下がってから再試行してください。原本は保存されています。"
    }
  }
}
