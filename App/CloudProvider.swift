import SwiftUI

/// A bring-your-own-key transcription provider. Answering uses `LLMProvider`.
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

  var supportsTranscription: Bool { self == .openAI || self == .deepgram }
}
