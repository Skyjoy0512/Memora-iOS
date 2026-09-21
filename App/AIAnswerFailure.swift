import Foundation

/// Why an answer could not be produced. Told apart so the app can say which
/// one it was instead of always blaming the engine.
enum AIAnswerFailure: Error, Equatable {
  /// No engine can run on this device at all.
  case noEngine
  /// The on-device model exists but is not ready yet.
  case engineNotReady
  /// An engine that needs a bundled model, which this build does not ship.
  case notBundled
  case missingKey
  /// The provider rejected the key.
  case unauthorized
  case rateLimited
  /// The provider answered with an error.
  case server
  case network
  /// The request was superseded, so there is nothing to show.
  case cancelled
  case empty
  /// The chosen provider cannot answer questions.
  case unsupportedProvider
  /// The question was only an attachment no engine can read.
  case attachmentNotAnalysed

  /// What to tell the person. Cancellation says nothing because a newer
  /// request has already replaced this one.
  var message: String {
    switch self {
    case .noEngine:
      "この端末ではAIエンジンを利用できません。設定の「AI整理」でクラウド（BYOK）を選ぶと回答できます。"
    case .engineNotReady:
      "端末内モデルの準備ができていません。少し待ってからもう一度お試しください。"
    case .notBundled:
      "ローカルLLMはこのアプリにまだ入っていません。設定の「AI整理」で別のエンジンを選んでください。"
    case .missingKey:
      "APIキーが設定されていません。設定の「AI整理」でキーを保存してください。"
    case .unauthorized:
      "APIキーが受け付けられませんでした。設定の「AI整理」でキーを確認してください。"
    case .rateLimited:
      "APIの利用上限に達しました。しばらく待ってからもう一度お試しください。"
    case .server:
      "AIのサーバーがエラーを返しました。時間をおいてもう一度お試しください。"
    case .network:
      "ネットワークに接続できませんでした。接続を確認してください。"
    case .cancelled:
      ""
    case .empty:
      "回答が空でした。もう一度お試しください。"
    case .unsupportedProvider:
      "このプロバイダーは回答作成に対応していません。設定の「AI整理」でOpenAIかAnthropicを選んでください。"
    case .attachmentNotAnalysed:
      "この添付はAIが読める形式ではないため、回答できません。質問を入力するか、テキスト・文字入りPDFを添付してください。"
    }
  }
}

/// The outcome of asking an engine: an answer, or the reason there is none.
enum AIAnswerResult {
  case answer(String)
  case failure(AIAnswerFailure)

  var text: String? {
    if case .answer(let text) = self { return text }
    return nil
  }

  var failure: AIAnswerFailure? {
    if case .failure(let reason) = self { return reason }
    return nil
  }
}
