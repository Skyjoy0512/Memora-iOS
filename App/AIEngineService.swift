import Foundation
import FoundationModels

/// Answers a question with the chosen AI engine, or returns nil so the caller
/// can fall back to its canned answer.
enum AIEngineService {
  static func answer(question: String, scopeLabel: String) async -> String? {
    let engine = AIEngine(
      rawValue: UserDefaults.standard.string(forKey: "memora.aiEngine") ?? ""
    ) ?? .automatic

    switch engine {
    case .foundation, .automatic:
      if #available(iOS 26.0, *) {
        return try? await FoundationModelAnswer.generate(question: question, scopeLabel: scopeLabel)
      }
      return nil

    case .local, .cloud:
      // Local LLM downloads and BYOK cloud calls are not wired yet.
      return nil
    }
  }
}

/// Apple's on-device `Foundation Models`, available from iOS 26.
@available(iOS 26.0, *)
private enum FoundationModelAnswer {
  enum Failure: Error {
    case unavailable
    case empty
  }

  static func generate(question: String, scopeLabel: String) async throws -> String {
    guard SystemLanguageModel.default.isAvailable else { throw Failure.unavailable }

    let session = LanguageModelSession(
      instructions: "あなたは会議の記録を要約して答えるアシスタントです。短い日本語で、記録に沿って答えます。"
    )
    let prompt = """
    対象: \(scopeLabel)
    質問: \(question)
    持っている会議の記録に基づいて簡潔に答えてください。
    """

    let response = try await session.respond(to: prompt)
    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw Failure.empty }
    return text
  }
}
