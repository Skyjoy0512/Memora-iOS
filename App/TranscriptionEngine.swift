import SwiftUI

/// How new recordings and imports are transcribed.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
  case automatic
  case speechAnalyzer
  case onDevice
  case cloud

  var id: Self { self }

  var label: String {
    switch self {
    case .automatic: "自動（おすすめ）"
    case .speechAnalyzer: "Apple SpeechAnalyzer"
    case .onDevice: "端末内（Whisper）"
    case .cloud: "クラウド（BYOK）"
    }
  }

  var detail: String {
    switch self {
    case .automatic:
      "対応状況に合わせて、端末内を優先して選びます。"
    case .speechAnalyzer:
      "iOS 26以降のSpeechAnalyzerで、音声を外部へ送らず処理します。"
    case .onDevice:
      "Whisperはモデルの同梱が必要で、この版では未接続です。"
    case .cloud:
      "APIキーを保存すると、選んだプロバイダーで文字起こしします。"
    }
  }

  var usesCloud: Bool { self == .cloud }
}
