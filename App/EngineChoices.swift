import Foundation

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

/// How summaries and Ask AI answers are produced.
enum AIEngine: String, CaseIterable, Identifiable {
  case automatic
  case foundation
  case local
  case cloud

  var id: Self { self }

  var label: String {
    switch self {
    case .automatic: "自動（おすすめ）"
    case .foundation: "Apple Foundation Models"
    case .local: "ローカルLLM"
    case .cloud: "クラウド（BYOK）"
    }
  }

  /// A short form for the composer chip, which has little room.
  var shortLabel: String {
    switch self {
    case .automatic: "自動"
    case .foundation: "端末内"
    case .local: "ローカル"
    case .cloud: "クラウド"
    }
  }

  var symbol: String {
    switch self {
    case .automatic: "sparkles"
    case .foundation: "iphone"
    case .local: "desktopcomputer"
    case .cloud: "cloud"
    }
  }

  var detail: String {
    switch self {
    case .automatic:
      "対応状況に合わせて、端末内を優先して選びます。"
    case .foundation:
      "iOS 26以降のFoundation Modelsで、端末内で整理します。"
    case .local:
      "ローカルLLMはモデルの同梱が必要で、この版では未接続です。"
    case .cloud:
      "APIキーを保存すると、選んだプロバイダーのAPIで回答します。"
    }
  }

  var usesCloud: Bool { self == .cloud }
}

/// A bring-your-own-key provider.
enum CloudProvider: String, CaseIterable, Identifiable {
  case openAI
  case anthropic
  case google
  case deepgram

  var id: Self { self }

  var label: String {
    switch self {
    case .openAI: "OpenAI"
    case .anthropic: "Anthropic"
    case .google: "Google Cloud"
    case .deepgram: "Deepgram"
    }
  }

  /// Which providers can answer questions rather than transcribe.
  var supportsAI: Bool { self == .openAI || self == .anthropic }
  var supportsTranscription: Bool { self == .openAI || self == .deepgram }
}

/// Spoken language preference.
enum RecognitionLanguage: String, CaseIterable, Identifiable {
  case japanese
  case english
  case automatic

  var id: Self { self }

  var label: String {
    switch self {
    case .japanese: "日本語"
    case .english: "英語"
    case .automatic: "自動検出"
    }
  }

  var locale: Locale {
    switch self {
    case .japanese: Locale(identifier: "ja-JP")
    case .english: Locale(identifier: "en-US")
    case .automatic: Locale.current
    }
  }
}
