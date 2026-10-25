import Foundation
import FoundationModels

/// Says which reason stopped the on-device model instead of blaming "not
/// ready" for everything. Shared by Ask AI and the summarizer.
@available(iOS 26.0, *)
enum FoundationModelFailure {
  static func reason(for error: Error) -> AIAnswerFailure {
    SummaryDiagnostics.current?.record(.onDeviceError, code: (error as NSError).code)
    if error is CancellationError { return .cancelled }
    // The error type differs before and after iOS 27.
    if #available(iOS 27.0, *) {
      if let modelError = error as? LanguageModelError {
        return reason(for: modelError)
      }
      if let modelError = error as? SystemLanguageModel.Error {
        switch modelError {
        case .assetsUnavailable: return .assetsUnavailable
        @unknown default: return .generationFailed
        }
      }
    } else if let generationError = error as? LanguageModelSession.GenerationError {
      return reason(for: generationError)
    }
    return .generationFailed
  }

  @available(iOS 27.0, *)
  private static func reason(for error: LanguageModelError) -> AIAnswerFailure {
    switch error {
    case .contextSizeExceeded: .contextTooLarge
    case .rateLimited: .rateLimited
    case .unsupportedLanguageOrLocale: .unsupportedLanguage
    case .guardrailViolation, .refusal: .guardrail
    case .timeout: .onDeviceTimedOut
    default: .generationFailed
    }
  }

  private static func reason(for error: LanguageModelSession.GenerationError) -> AIAnswerFailure {
    switch error {
    case .exceededContextWindowSize: .contextTooLarge
    case .rateLimited: .rateLimited
    case .unsupportedLanguageOrLocale: .unsupportedLanguage
    case .guardrailViolation, .refusal: .guardrail
    case .assetsUnavailable: .assetsUnavailable
    default: .generationFailed
    }
  }
}
