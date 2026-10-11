import Foundation

enum SpeakerProcessingFailure: LocalizedError {
  case modelsMissing, assetsInvalid, busy, noSpeech, multipleSpeakers, clippedAudio, invalidEmbedding
  case profileUnavailable, modelMismatch, storageFailure

  var errorDescription: String? {
    switch self {
    case .modelsMissing: "設定の「話者識別」で音声モデルをダウンロードしてください。通常の録音・文字起こしは引き続き利用できます。"
    case .assetsInvalid: "音声モデルを検証できませんでした。モデルを再ダウンロードしてください。"
    case .busy: "別の音声解析が実行中です。完了してからもう一度お試しください。"
    case .noSpeech: "十分な発話を検出できませんでした。静かな場所で自然な声を録音してください。"
    case .multipleSpeakers: "複数の話者または発話の重なりを検出しました。自分だけで録音し直してください。"
    case .clippedAudio: "音割れの可能性がある最大音量を検出しました。端末から少し離れて録音し直してください。"
    case .invalidEmbedding: "声の特徴量を生成できませんでした。録音し直してください。"
    case .profileUnavailable: "声のプロフィールを読み込めません。端末のロックを解除するか、再登録してください。"
    case .modelMismatch: "声のモデルが変更されています。自分の声を再登録してください。"
    case .storageFailure: "声のプロフィールを安全に保存できませんでした。端末の保存状態を確認してください。"
    }
  }
}
