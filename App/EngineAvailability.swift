import Foundation
import Speech
import FoundationModels

/// What an engine can actually do on this device right now. Settings and the run
/// paths both ask here, so what the screen promises and what runs cannot
/// disagree, and a missing key or unsupported language is visible before a job
/// starts rather than after it fails.
@MainActor
enum EngineAvailability {
  /// A reason an engine cannot run.
  enum Limit: Equatable {
    /// The engine needs a newer system than this device has.
    case needsNewerOS
    /// The engine does not handle the chosen language.
    case unsupportedLanguage(String)
    /// The provider needs an API key that has not been saved.
    case missingKey(String)
    /// An engine that needs a bundled model this build does not ship.
    case notBundled
    /// The engine exists but this device cannot run it.
    case deviceNotSupported

    var shortLabel: String {
      switch self {
      case .needsNewerOS: "このOSでは未対応"
      case .unsupportedLanguage(let language): "\(language)に未対応"
      case .missingKey: "APIキー未設定"
      case .notBundled: "モデル未同梱"
      case .deviceNotSupported: "この端末では未対応"
      }
    }

    var message: String {
      switch self {
      case .needsNewerOS:
        "この機能は新しいOSで利用できます。ソフトウェアアップデートを確認してください。"
      case .unsupportedLanguage(let language):
        "選んだエンジンは\(language)に対応していません。設定の「文字起こし」で言語を変えるか、クラウドを選んでください。"
      case .missingKey(let feature):
        "\(feature)のAPIキーが設定されていません。設定から入力してください。"
      case .notBundled:
        "このモデルはまだアプリに入っていません。設定で別のエンジンを選んでください。"
      case .deviceNotSupported:
        "この端末では利用できません。設定で別のエンジンを選んでください。"
      }
    }
  }

  struct Status: Equatable {
    var limits: [Limit] = []

    var isReady: Bool { limits.isEmpty }

    /// A short phrase for a settings row.
    var summary: String {
      limits.first?.shortLabel ?? "利用できます"
    }

    /// The full sentence for the first reason, for a footer or an alert.
    var message: String? {
      limits.first?.message
    }
  }

  /// The settings keys and engine choices, read in one place so the screens and
  /// the run paths always describe the same configuration.
  static func currentTranscriptionEngine() -> TranscriptionEngine {
    TranscriptionEngine(
      rawValue: UserDefaults.standard.string(forKey: "memora.transcriptionEngine") ?? ""
    ) ?? .automatic
  }

  static func currentTranscriptionLanguage() -> RecognitionLanguage {
    RecognitionLanguage(
      rawValue: UserDefaults.standard.string(forKey: "memora.transcriptionLanguage") ?? ""
    ) ?? .japanese
  }

  static func currentTranscriptionProvider() -> CloudProvider {
    CloudProvider(
      rawValue: UserDefaults.standard.string(forKey: "memora.transcriptionProvider") ?? ""
    ) ?? .openAI
  }

  static func hasKey(_ account: String) -> Bool {
    guard let key = KeychainStore.string(forKey: account) else { return false }
    return !key.isEmpty
  }

  /// Whether the chosen transcription engine can run, including whether the
  /// language is supported and the model is installed.
  static func transcription(
    _ engine: TranscriptionEngine,
    language: RecognitionLanguage,
    provider: CloudProvider
  ) async -> Status {
    switch engine {
    case .automatic, .speechAnalyzer:
      guard #available(iOS 26.0, *) else {
        return Status(limits: [.needsNewerOS])
      }
      guard SpeechTranscriber.isAvailable else {
        return Status(limits: [.deviceNotSupported])
      }
      guard await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) != nil else {
        return Status(limits: [.unsupportedLanguage(language.label)])
      }
      return Status()

    case .onDevice:
      return Status(limits: [.notBundled])

    case .cloud:
      guard provider.supportsTranscription else {
        return Status(limits: [.deviceNotSupported])
      }
      guard hasKey("transcription.\(provider.rawValue)") else {
        return Status(limits: [.missingKey("クラウド文字起こし")])
      }
      return Status()
    }
  }

  /// Whether the chosen AI engine can answer.
  static func ai(_ engine: AIEngine, provider: LLMProvider) -> Status {
    switch engine {
    case .automatic:
      if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
        return Status()
      }
      return Status(limits: [.deviceNotSupported])

    case .foundation:
      guard #available(iOS 26.0, *) else { return Status(limits: [.needsNewerOS]) }
      return SystemLanguageModel.default.isAvailable
        ? Status()
        : Status(limits: [.deviceNotSupported])

    case .local:
      return Status(limits: [.notBundled])

    case .cloud:
      return hasKey(provider.keychainAccount)
        ? Status()
        : Status(limits: [.missingKey("AI")])
    }
  }
}
