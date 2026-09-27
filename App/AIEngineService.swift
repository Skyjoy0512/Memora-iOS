import Foundation
import FoundationModels

/// Answers a question with the chosen engine, or says which reason stopped it.
enum AIEngineService {
  /// The engine that will actually run: 自動 resolves to the on-device model
  /// when this device has one, so the app can name what really answered.
  static func effectiveEngine(_ engine: AIEngine) -> AIEngine {
    guard engine == .automatic else { return engine }
    if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
      return .foundation
    }
    return .automatic
  }

  /// The provider's model name, so the app shows what was called rather than a
  /// label that could drift from it.
  static func modelLabel(engine: AIEngine, llm: LLMSelection) -> String? {
    effectiveEngine(engine) == .cloud ? llm.modelLabel : nil
  }

  /// The most characters of context one engine is given. Kept in one place so
  /// the on-device and cloud limits cannot drift apart between requests. The
  /// on-device model's window is about 4,096 tokens and covers the instructions,
  /// the history, and the answer too, so only half of it is spent on the records
  /// and the rest is left as room; Japanese runs about one token per character.
  static let defaultContextCharacterLimit = 2_000

  static func contextCharacterLimit(for engine: AIEngine) -> Int {
    guard effectiveEngine(engine) != .cloud else { return 40_000 }
    if #available(iOS 26.0, *) {
      return max(1_000, SystemLanguageModel.default.contextSize / 2)
    }
    return defaultContextCharacterLimit
  }

  static func answer(
    engine: AIEngine,
    llm: LLMSelection,
    question: String,
    scopeLabel: String,
    context: String,
    history: String
  ) async -> AIAnswerResult {
    switch effectiveEngine(engine) {
    case .foundation, .automatic:
      guard #available(iOS 26.0, *) else { return .failure(.noEngine) }
      return await FoundationModelAnswer.generate(
        question: question,
        scopeLabel: scopeLabel,
        context: context,
        history: history
      )

    case .local:
      // A local LLM still needs a bundled model; this build has none.
      return .failure(.notBundled)

    case .cloud:
      return await CloudAIService.answer(
        question: question,
        scopeLabel: scopeLabel,
        context: context,
        history: history,
        llm: llm
      )
    }
  }
}

/// Apple's on-device `Foundation Models`, available from iOS 26.
@available(iOS 26.0, *)
private enum FoundationModelAnswer {
  static func generate(
    question: String,
    scopeLabel: String,
    context: String,
    history: String
  ) async -> AIAnswerResult {
    guard SystemLanguageModel.default.isAvailable else { return .failure(.noEngine) }

    let session = LanguageModelSession(
      instructions: "あなたは会議の記録を要約して答えるアシスタントです。短い日本語で、与えられた記録だけに沿って答えます。"
    )
    let prompt = AIAnswerPrompt.text(
      question: question,
      scopeLabel: scopeLabel,
      context: context,
      history: history
    )

    do {
      let response = try await session.respond(to: prompt)
      let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? .failure(.empty) : .answer(text)
    } catch is CancellationError {
      return .failure(.cancelled)
    } catch {
      // Say which reason stopped the model instead of blaming "not ready" for
      // everything. The error type differs before and after iOS 27.
      if #available(iOS 27.0, *) {
        if let modelError = error as? LanguageModelError {
          return Self.failure(from: modelError)
        }
      } else if let generationError = error as? LanguageModelSession.GenerationError {
        return Self.failure(from: generationError)
      }
      return .failure(.engineNotReady)
    }
  }

  @available(iOS 27.0, *)
  private static func failure(from error: LanguageModelError) -> AIAnswerResult {
    switch error {
    case .contextSizeExceeded: .failure(.contextTooLarge)
    case .rateLimited: .failure(.rateLimited)
    case .unsupportedLanguageOrLocale: .failure(.unsupportedLanguage)
    case .guardrailViolation, .refusal: .failure(.guardrail)
    default: .failure(.engineNotReady)
    }
  }

  private static func failure(from error: LanguageModelSession.GenerationError) -> AIAnswerResult {
    switch error {
    case .exceededContextWindowSize: .failure(.contextTooLarge)
    case .rateLimited: .failure(.rateLimited)
    case .unsupportedLanguageOrLocale: .failure(.unsupportedLanguage)
    case .guardrailViolation, .refusal: .failure(.guardrail)
    case .assetsUnavailable: .failure(.assetsUnavailable)
    default: .failure(.engineNotReady)
    }
  }
}
