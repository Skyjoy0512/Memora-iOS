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
  static func modelLabel(engine: AIEngine, provider: CloudProvider) -> String? {
    effectiveEngine(engine) == .cloud ? provider.aiModelName : nil
  }

  /// The most characters of context one engine is given. Kept in one place so
  /// the on-device and cloud limits cannot drift apart between requests.
  static let defaultContextCharacterLimit = 6_000

  static func contextCharacterLimit(for engine: AIEngine) -> Int {
    effectiveEngine(engine) == .cloud ? 40_000 : defaultContextCharacterLimit
  }

  static func answer(
    engine: AIEngine,
    provider: CloudProvider,
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
      guard provider.supportsAI else { return .failure(.unsupportedProvider) }
      return await CloudAIService.answer(
        question: question,
        scopeLabel: scopeLabel,
        context: context,
        history: history,
        provider: provider
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
      return .failure(.engineNotReady)
    }
  }
}

/// The prompt both engines send, so the two ask for the same thing.
enum AIAnswerPrompt {
  static func text(question: String, scopeLabel: String, context: String, history: String) -> String {
    """
    対象: \(scopeLabel)

    \(history.isEmpty ? "" : "これまでのやりとり:\n\(history)\n")
    \(context.isEmpty ? "" : "記録:\n\(context)\n")
    質問: \(question)
    記録に基づいて簡潔に答えてください。記録に無いことは推測せず、無いと伝えてください。
    """
  }
}
