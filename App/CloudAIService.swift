import Foundation

/// Asks a provider's API for an answer using the person's own key.
enum CloudAIService {
  static func answer(
    question: String,
    scopeLabel: String,
    context: String,
    history: String,
    provider: CloudProvider
  ) async -> AIAnswerResult {
    guard let key = KeychainStore.string(forKey: "ai.\(provider.rawValue)"), !key.isEmpty else {
      return .failure(.missingKey)
    }

    let system = "あなたは会議の記録を要約して答えるアシスタントです。短い日本語で、与えられた記録だけに沿って答えます。"
    let user = AIAnswerPrompt.text(
      question: question,
      scopeLabel: scopeLabel,
      context: context,
      history: history
    )

    do {
      switch provider {
      case .openAI:
        return .answer(try await openAI(system: system, user: user, key: key))
      case .anthropic:
        return .answer(try await anthropic(system: system, user: user, key: key))
      case .google, .deepgram:
        return .failure(.unsupportedProvider)
      }
    } catch let failure as AIAnswerFailure {
      return .failure(failure)
    } catch is CancellationError {
      return .failure(.cancelled)
    } catch let error as URLError {
      return .failure(error.code == .cancelled ? .cancelled : .network)
    } catch {
      return .failure(.network)
    }
  }

  private static func openAI(system: String, user: String, key: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": CloudProvider.openAI.aiModelName,
      "temperature": 0.2,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user]
      ]
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
    guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
      throw AIAnswerFailure.empty
    }
    return text
  }

  private static func anthropic(system: String, user: String, key: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": CloudProvider.anthropic.aiModelName,
      "max_tokens": 500,
      "system": system,
      "messages": [["role": "user", "content": user]]
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
    guard let text = decoded.content.first?.text, !text.isEmpty else {
      throw AIAnswerFailure.empty
    }
    return text
  }

  /// Turns the provider's status into the reason it failed, so a wrong key and
  /// a busy API are not reported as the same thing.
  private static func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw AIAnswerFailure.network }
    switch http.statusCode {
    case 200..<300:
      return
    case 401, 403:
      throw AIAnswerFailure.unauthorized
    case 429:
      throw AIAnswerFailure.rateLimited
    default:
      throw AIAnswerFailure.server
    }
  }
}

extension CloudProvider {
  /// The model this provider is called with. Shown in the answer's details so
  /// the display cannot drift from the request.
  var aiModelName: String {
    switch self {
    case .openAI: "gpt-4o-mini"
    case .anthropic: "claude-3-5-haiku-latest"
    case .google: "—"
    case .deepgram: "—"
    }
  }
}

private struct OpenAIResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable { var content: String }
    var message: Message
  }
  var choices: [Choice]
}

private struct AnthropicResponse: Decodable {
  struct Block: Decodable { var text: String? }
  var content: [Block]
}
