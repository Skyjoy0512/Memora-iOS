import SwiftUI

/// How summaries and Ask AI answers are produced.
enum AIEngine: String, CaseIterable, Identifiable, Codable {
  case automatic
  /// Memora's own cloud AI, paid with plan credits instead of a key.
  case memora
  case foundation
  case local
  case cloud

  var id: Self { self }

  var label: String {
    switch self {
    case .automatic: "おまかせ"
    case .memora: "Memora Intelligence"
    case .foundation: "端末内AI"
    case .local: "ローカルLLM"
    case .cloud: "クラウドAI"
    }
  }

  /// A short form for the composer chip, which has little room.
  var shortLabel: String {
    switch self {
    case .automatic: "自動"
    case .memora: "Memora"
    case .foundation: "端末内"
    case .local: "ローカル"
    case .cloud: "クラウド"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .automatic: .sparkles
    case .memora: .sparklesRectangleStack
    case .foundation: .appleLogo
    case .local: .cpu
    case .cloud: .cloud
    }
  }

  var detail: String {
    switch self {
    case .automatic:
      "対応端末ではAppleの端末内モデルを使います。未対応時は別のエンジンを選んでください。"
    case .memora:
      "キーなしで使えるMemoraのクラウドAI。プランのAIクレジットを使います（ライト以上）。"
    case .foundation:
      "iOS 26以降のFoundation Modelsで、端末内で整理します。"
    case .local:
      "通常のAsk AIでの利用は準備中です。Live専用モデルは、音声会話のモデル画面から導入できます。"
    case .cloud:
      "APIキーを保存すると、選んだプロバイダーのAPIで回答します。"
    }
  }

  var usesCloud: Bool { self == .cloud }

  /// False for engines this build cannot run, so the choice is visible but not
  /// selectable instead of failing after it is picked.
  var isSelectable: Bool { self != .local }
}
