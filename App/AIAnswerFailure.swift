import Foundation

/// Why an answer could not be produced. Told apart so the app can say which
/// one it was instead of always blaming the engine.
enum AIAnswerFailure: Error, Equatable {
  /// No engine can run on this device at all.
  case noEngine
  /// The on-device model exists but is not ready yet.
  case engineNotReady
  /// The request was larger than the on-device model's context, even after a
  /// smaller retry.
  case contextTooLarge
  /// The on-device model does not support the language of the request.
  case unsupportedLanguage
  /// The on-device model declined for a safety reason.
  case guardrail
  /// The on-device model's assets are not available on this device.
  case assetsUnavailable
  /// An engine that needs a bundled model, which this build does not ship.
  case notBundled
  case missingKey
  /// The provider rejected the key.
  case unauthorized
  /// The chosen model id does not exist for this key, usually because the
  /// provider renamed or retired it.
  case modelUnavailable
  /// The model declined to answer for a safety reason.
  case refused
  case rateLimited
  /// The provider answered with an error.
  case server
  case network
  /// The provider did not answer in time. Long summaries take minutes, so this
  /// is told apart from having no connection at all.
  case timedOut
  case providerTimedOut
  case providerUnavailable
  case providerInterrupted
  case generationFailed
  case onDeviceTimedOut
  /// The connection dropped mid-answer, usually because the app left the
  /// screen while a long answer was still being written.
  case connectionLost
  case contextChanged
  case recordAccessDenied
  /// The request was superseded, so there is nothing to show.
  case cancelled
  case empty
  /// The chosen provider cannot answer questions.
  case unsupportedProvider
  /// The question was only an attachment no engine can read.
  case attachmentNotAnalysed
  case recordContentUnavailable
  /// Memora Intelligence refused: the month's credits are used up.
  case outOfCredits
  /// Memora Intelligence is chosen but its server is not connected yet.
  case serviceNotConnected
  case executionLimit

  /// What to tell the person. Cancellation says nothing because a newer
  /// request has already replaced this one.
  var message: String {
    switch self {
    case .noEngine:
      "この端末ではAIエンジンを利用できません。設定の「AI整理」でクラウド（BYOK）を選ぶと回答できます。"
    case .engineNotReady:
      "端末内モデルの準備ができていません。少し待ってからもう一度お試しください。"
    case .contextTooLarge:
      "記録が長すぎて端末内AIでは扱えません。範囲を絞るか、クラウドを選んでください。"
    case .unsupportedLanguage:
      "この言語は端末内AIが対応していません。設定の「AI整理」でクラウド（BYOK）を選ぶと回答できます。"
    case .guardrail:
      "安全上の理由で端末内AIが回答を控えました。質問や記録の内容を変えてお試しください。"
    case .assetsUnavailable:
      "端末内モデルの準備ができていません。少し待ってからもう一度お試しください。"
    case .notBundled:
      "ローカルLLMはこのアプリにまだ入っていません。設定の「AI整理」で別のエンジンを選んでください。"
    case .missingKey:
      "APIキーが設定されていません。設定の「AI整理」でキーを保存してください。"
    case .outOfCredits:
      "今月のAIクレジットを使い切りました（APIの残高不足の場合もあります）。プランを変えるか、来月まで端末内AIをお使いください。"
    case .serviceNotConnected:
      "Memora Intelligenceはまだ接続されていません。設定の「AI整理」で端末内AIか自分のAPIキーを選んでください。"
    case .unauthorized:
      "APIキーが受け付けられませんでした。設定の「AI整理」でキーを確認してください。"
    case .modelUnavailable:
      "選んだモデルはこのAPIキーでは使えません。設定の「AI整理」でモデルを選び直してください。"
    case .refused:
      "安全上の理由でAIが回答を控えました。質問や記録の内容を変えてお試しください。"
    case .rateLimited:
      "APIの利用上限か残高の上限に達しました。しばらく待つか、プロバイダーの管理画面で残高を確認してください。"
    case .server:
      "AIのサーバーがエラーを返しました。時間をおいてもう一度お試しください。"
    case .timedOut:
      "AIとの通信が待機時間の上限に達しました。送信済みの場合は、プロバイダー側で処理・課金が続いている可能性があります。"
    case .providerTimedOut:
      "AIサービスまたは中継サーバーが時間切れを返しました（HTTP 408/504）。処理・課金が済んでいる可能性があるため、利用履歴を確認してから再試行してください。"
    case .providerUnavailable:
      "AIサービスまたは中継サーバーが一時的に利用できません（HTTP 502/503）。自動再送はしていません。"
    case .providerInterrupted:
      "AIサービスが生成を中断しました。完成した要約は受け取っていません。処理・課金が済んでいる可能性があるため、利用履歴を確認してから再試行してください。"
    case .generationFailed:
      "端末内AIの生成中にエラーが発生しました。原文と保存済みの要約は保持しています。原因を確認して再試行してください。"
    case .onDeviceTimedOut:
      "端末内AIが1回の生成時間の上限に達しました。通信のタイムアウトではありません。原文は保存されています。範囲を短くするか、別のAIを選んでください。"
    case .connectionLost:
      "AIとの通信が途中で切れました。要約が終わるまで、アプリを開いたままにしてお試しください。"
    case .contextChanged:
      "参照する情報・所属・許可が変わったため、回答を停止しました。現在の内容を確認して、もう一度質問してください。"
    case .recordAccessDenied:
      "この記録は外部AIへの送信が許可されていません。記録のプライバシー設定で許可するか、端末内AIを選んでください。内容は送信していません。"
    case .network:
      "ネットワークに接続できませんでした。接続を確認してください。"
    case .cancelled:
      ""
    case .empty:
      "回答が空でした。もう一度お試しください。"
    case .unsupportedProvider:
      "このプロバイダーは回答作成に対応していません。設定の「AI整理」で別のプロバイダーを選んでください。"
    case .attachmentNotAnalysed:
      "添付の文字を読めないため、回答を開始していません。テキスト・PDF・文字を含む画像に変更するか、添付を外してもう一度送信してください。"
    case .recordContentUnavailable:
      "この記録にはAIが参照できる本文がありません。文字起こし・要約・メモを追加するか、読める資料を添付してください。記録と保存済みファイルはそのままです。"
    case .executionLimit:
      "この依頼の実行時間またはデータ量の上限に達したため停止しました。作業は未完了です。実行済みの操作を確認し、必要な続きだけを依頼してください。"
    }
  }
}
