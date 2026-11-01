import Foundation
import FoundationModels

/// Answers a question with the chosen engine, or says which reason stopped it.
enum AIEngineService {
  /// The engine that will actually run: 自動 resolves to the on-device model
  /// when this device has one, so the app can name what really answered.
  static func effectiveEngine(_ engine: AIEngine) -> AIEngine {
    // Memora Intelligence runs on the cloud path, aimed at Memora's server.
    guard engine == .automatic else { return engine == .memora ? .cloud : engine }
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

  /// The context room for one request. A cloud model is never held to a single
  /// fixed character count: its declared window, the answer's reservation and
  /// a safety margin decide the budget, and deep work asks for more of it.
  /// Without a selection the conservative profile is used, which still beats
  /// the old flat limit on every model that supports a normal window.
  static func contextCharacterLimit(for engine: AIEngine, llm: LLMSelection? = nil,
                                    task: ContextTaskKind = .chat) -> Int {
    guard effectiveEngine(engine) != .cloud else {
      let capabilities = llm.map { ModelCapabilities.resolve(llm: $0) }
        ?? .conservative(provider: .openAI, modelID: "unknown")
      return TokenBudgetManager.budget(capabilities: capabilities, task: task).inputCharacterBudget
    }
    if #available(iOS 26.0, *) {
      return max(1_000, SystemLanguageModel.default.contextSize / 2)
    }
    return defaultContextCharacterLimit
  }

  static func tokenBudget(for engine: AIEngine, llm: LLMSelection?, task: ContextTaskKind) -> TokenBudget {
    let capabilities = llm.map { ModelCapabilities.resolve(llm: $0) }
      ?? .conservative(provider: .openAI, modelID: "unknown")
    return TokenBudgetManager.budget(capabilities: capabilities, task: task)
  }

  static func answer(
    engine: AIEngine,
    llm: LLMSelection,
    question: String,
    scopeLabel: String,
    context: String,
    history: String,
    onText: (@MainActor (String) -> Void)? = nil
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

    case .cloud, .memora:
      return await CloudAIService.answer(
        question: question,
        scopeLabel: scopeLabel,
        context: context,
        history: history,
        llm: llm,
        onText: onText
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
      instructions: AIAnswerPrompt.grounding + "\n" + ReadabilityGuide.compactRules
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
    } catch {
      return .failure(FoundationModelFailure.reason(for: error))
    }
  }
}
