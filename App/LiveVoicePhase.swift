import Foundation

enum LiveVoicePhase: Equatable {
  case idle, preparing, loadingRecognitionModel, listening, thinking, speaking, paused, needsReview, waitingForInteraction
  case failed(String)

  var label: String {
    switch self {
    case .idle: "マイクを押してLiveを開始"
    case .preparing: "Liveを準備しています"
    case .loadingRecognitionModel: "日本語の音声認識モデルを準備しています。初回はダウンロードが必要です"
    case .listening: "聞いています。話し終わると自動送信"
    case .thinking: "回答を準備しています。話しかけて割り込み"
    case .speaking: "読み上げています。話しかけて割り込み"
    case .paused: "Liveを一時停止しました"
    case .waitingForInteraction: "確認を待っています。画面で承認・回答してください"
    case .needsReview: "入力を保持しました。Liveを閉じて送信内容を確認してください"
    case .failed(let reason): reason
    }
  }
}
